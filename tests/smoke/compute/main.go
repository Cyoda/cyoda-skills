// Command compute is the smoke-test compute member for scenario 07. It is
// test harness only: the compute skill stays language-agnostic and must not
// copy this code.
//
// It joins cyoda-go over gRPC with the tag "smoke-compute" and serves the
// workflows in cyoda/skills/compute/examples/cascade:
//
//   - function criterion has-address: matches:false with the reason
//     "missing shipping address" when $.address is absent or blank.
//   - processor create-shipment: creates a shipment linked by $.orderId,
//     fires the shipment's manual transition "dispatch", and returns the order
//     with $.shipmentId set. Both REST callbacks echo the dispatch's
//     cyodatxtoken as X-Tx-Token, so they commit or roll back with the order.
//
// Protocol facts: cyoda help grpc (CONNECTION, COMPUTE MEMBER PROTOCOL,
// KEEPALIVE, TAG ROUTING, MESSAGE TYPES) and cyoda help cluster
// (COMPUTE CALLBACK TRANSACTION ROUTING). It prints READY once joined.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"

	cepb "github.com/cyoda-platform/cyoda-go/api/grpc/cloudevents"
	cyodapb "github.com/cyoda-platform/cyoda-go/api/grpc/cyoda"
)

const (
	tag           = "smoke-compute"
	shipmentModel = "shipment/1"
	txTokenAttr   = "cyodatxtoken"

	typeJoin       = "CalculationMemberJoinEvent"
	typeGreet      = "CalculationMemberGreetEvent"
	typeKeepAlive  = "CalculationMemberKeepAliveEvent"
	typeProcReq    = "EntityProcessorCalculationRequest"
	typeProcResp   = "EntityProcessorCalculationResponse"
	typeCritReq    = "EntityCriteriaCalculationRequest"
	typeCritResp   = "EntityCriteriaCalculationResponse"
	typeAck        = "EventAckResponse"
	missingAddress = "missing shipping address"
)

type stream = grpc.BidiStreamingClient[cepb.CloudEvent, cepb.CloudEvent]

// member holds the send queue (one writer per stream) and the requestId cache.
type member struct {
	out     chan *cepb.CloudEvent
	httpURL string
	token   string
	hc      *http.Client

	mu       sync.Mutex
	done     map[string]*cepb.CloudEvent // requestId -> answer already sent
	inFlight map[string]bool
}

// request is the part of a processor or criteria request this member reads.
type request struct {
	RequestID     string `json:"requestId"`
	EntityID      string `json:"entityId"`
	ProcessorName string `json:"processorName"`
	CriteriaName  string `json:"criteriaName"`
	Payload       *struct {
		Data map[string]any `json:"data"`
	} `json:"payload"`
}

func main() {
	grpcAddr := flag.String("grpc", "localhost:19090", "cyoda-go gRPC endpoint (host:port)")
	httpURL := flag.String("http", "http://localhost:18080/api", "cyoda-go REST base, including /api")
	token := flag.String("token", os.Getenv("CYODA_COMPUTE_TOKEN"), "bearer token (empty in mock auth mode)")
	tenant := flag.String("tenant", "mock-tenant", "joinedLegalEntityId: the token's tenant")
	flag.Parse()
	log.SetFlags(log.Ltime | log.Lmicroseconds)

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	if err := run(ctx, *grpcAddr, *httpURL, *token, *tenant); err != nil && ctx.Err() == nil {
		log.Fatalf("compute member: %v", err)
	}
}

func run(ctx context.Context, grpcAddr, httpURL, token, tenant string) error {
	conn, err := grpc.NewClient(grpcAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return fmt.Errorf("dial %s: %w", grpcAddr, err)
	}
	defer conn.Close()

	if token != "" {
		ctx = metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+token)
	}
	st, err := cyodapb.NewCloudEventsServiceClient(conn).StartStreaming(ctx)
	if err != nil {
		return fmt.Errorf("startStreaming: %w", err)
	}

	m := &member{
		out:      make(chan *cepb.CloudEvent, 64),
		httpURL:  strings.TrimRight(httpURL, "/"),
		token:    token,
		hc:       &http.Client{Timeout: 8 * time.Second},
		done:     map[string]*cepb.CloudEvent{},
		inFlight: map[string]bool{},
	}
	writeErr := make(chan error, 1)
	go m.writer(st, writeErr)

	// Join first; the greet is always the first event back.
	m.out <- event(typeJoin, map[string]any{
		"id":                  uuid.NewString(),
		"tags":                []string{tag},
		"joinedLegalEntityId": tenant,
	})
	greet, err := st.Recv()
	if err != nil {
		return fmt.Errorf("waiting for greet: %w", err)
	}
	if greet.GetType() != typeGreet {
		return fmt.Errorf("first event is %q, want %s", greet.GetType(), typeGreet)
	}
	var g struct {
		MemberID string `json:"memberId"`
		Success  *bool  `json:"success"`
	}
	if err := json.Unmarshal([]byte(greet.GetTextData()), &g); err != nil {
		return fmt.Errorf("greet payload: %w", err)
	}
	if g.Success != nil && !*g.Success {
		return fmt.Errorf("join refused: %s", greet.GetTextData())
	}
	m.ack(greet)
	log.Printf("joined as member %s with tags [%s]", g.MemberID, tag)
	fmt.Println("READY")

	// Read continuously; handle requests off the read loop so keep-alives
	// are acknowledged while a processor is calling back into cyoda.
	for {
		select {
		case err := <-writeErr:
			return fmt.Errorf("send: %w", err)
		default:
		}
		ev, err := st.Recv()
		if err != nil {
			if errors.Is(err, io.EOF) {
				return errors.New("server closed the stream")
			}
			return fmt.Errorf("recv: %w", err)
		}
		switch ev.GetType() {
		case typeKeepAlive:
			m.ack(ev)
		case typeProcReq, typeCritReq:
			go m.handle(ctx, ev)
		default:
			log.Printf("ignoring event type %s", ev.GetType())
		}
	}
}

// writer is the only goroutine that calls Send on the stream.
func (m *member) writer(st stream, errc chan<- error) {
	for ev := range m.out {
		if err := st.Send(ev); err != nil {
			errc <- err
			return
		}
	}
}

// ack answers a server event that needs no other response (greet, keep-alive).
func (m *member) ack(ev *cepb.CloudEvent) {
	m.out <- event(typeAck, map[string]any{"id": uuid.NewString(), "sourceEventId": ev.GetId(), "success": true})
}

// handle answers one processor or criteria request, at most once per requestId.
func (m *member) handle(ctx context.Context, ev *cepb.CloudEvent) {
	var req request
	if err := json.Unmarshal([]byte(ev.GetTextData()), &req); err != nil {
		log.Printf("malformed %s: %v", ev.GetType(), err)
		return
	}
	m.mu.Lock()
	if prev, ok := m.done[req.RequestID]; ok {
		m.mu.Unlock()
		m.out <- prev // a retried request gets the same answer
		return
	}
	if m.inFlight[req.RequestID] {
		m.mu.Unlock()
		return // the first copy will answer
	}
	m.inFlight[req.RequestID] = true
	m.mu.Unlock()

	var resp *cepb.CloudEvent
	if ev.GetType() == typeCritReq {
		resp = m.criterion(req)
	} else {
		resp = m.processor(ctx, req, txToken(ev))
	}

	m.mu.Lock()
	delete(m.inFlight, req.RequestID)
	m.done[req.RequestID] = resp
	m.mu.Unlock()
	m.out <- resp
}

func (m *member) criterion(req request) *cepb.CloudEvent {
	body := map[string]any{"id": uuid.NewString(), "requestId": req.RequestID, "entityId": req.EntityID, "success": true}
	switch req.CriteriaName {
	case "has-address":
		addr, _ := data(req)["address"].(string)
		ok := strings.TrimSpace(addr) != ""
		body["matches"] = ok
		if !ok {
			body["reason"] = missingAddress
		}
		log.Printf("has-address entity=%s matches=%v", req.EntityID, ok)
	default:
		body["success"] = false
		body["error"] = map[string]any{"code": "UNKNOWN_CRITERION", "message": "unknown criterion " + req.CriteriaName}
	}
	return event(typeCritResp, body)
}

func (m *member) processor(ctx context.Context, req request, tx string) *cepb.CloudEvent {
	body := map[string]any{"id": uuid.NewString(), "requestId": req.RequestID, "entityId": req.EntityID, "success": true}
	fail := func(err error) *cepb.CloudEvent {
		log.Printf("%s entity=%s failed: %v", req.ProcessorName, req.EntityID, err)
		body["success"] = false
		body["error"] = map[string]any{"code": "PROCESSOR_ERROR", "message": err.Error()}
		return event(typeProcResp, body)
	}
	if req.ProcessorName != "create-shipment" {
		return fail(fmt.Errorf("unknown processor %s", req.ProcessorName))
	}
	order := data(req)
	orderID, _ := order["orderId"].(string)
	if orderID == "" {
		return fail(errors.New("order has no $.orderId"))
	}

	// Create the linked shipment (POST /entity/JSON/{entityName}/{modelVersion}).
	link, _ := json.Marshal(map[string]any{"orderId": orderID})
	var created []struct {
		EntityIDs []string `json:"entityIds"`
	}
	if err := m.call(ctx, http.MethodPost, "/entity/JSON/"+shipmentModel, "application/json", link, tx, &created); err != nil {
		return fail(fmt.Errorf("create shipment: %w", err))
	}
	if len(created) == 0 || len(created[0].EntityIDs) == 0 {
		return fail(errors.New("create shipment: no entity id in response"))
	}
	shipID := created[0].EntityIDs[0]

	// Event cascade: fire the shipment's manual transition.
	if err := m.call(ctx, http.MethodPatch, "/entity/JSON/"+shipID+"/dispatch", "application/merge-patch+json", []byte("{}"), tx, nil); err != nil {
		return fail(fmt.Errorf("dispatch shipment %s: %w", shipID, err))
	}

	order["shipmentId"] = shipID
	body["payload"] = map[string]any{"type": "JSON", "data": order}
	log.Printf("create-shipment order=%s shipment=%s tx-token=%v", req.EntityID, shipID, tx != "")
	return event(typeProcResp, body)
}

// call issues a REST callback, echoing the tx-token so it joins the dispatch's transaction.
func (m *member) call(ctx context.Context, method, path, ctype string, body []byte, tx string, out any) error {
	r, err := http.NewRequestWithContext(ctx, method, m.httpURL+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	r.Header.Set("Content-Type", ctype)
	if method == http.MethodPatch {
		r.Header.Set("If-Match", "*")
	}
	if m.token != "" {
		r.Header.Set("Authorization", "Bearer "+m.token)
	}
	if tx != "" {
		r.Header.Set("X-Tx-Token", tx)
	}
	resp, err := m.hc.Do(r)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("%s %s -> %d %s", method, path, resp.StatusCode, raw)
	}
	if out != nil {
		return json.Unmarshal(raw, out)
	}
	return nil
}

func data(req request) map[string]any {
	if req.Payload == nil || req.Payload.Data == nil {
		return map[string]any{}
	}
	return req.Payload.Data
}

func txToken(ev *cepb.CloudEvent) string {
	if v, ok := ev.GetAttributes()[txTokenAttr]; ok {
		return v.GetCeString()
	}
	return ""
}

// event wraps a JSON payload in a CloudEvent whose id matches the payload's id.
func event(typ string, payload map[string]any) *cepb.CloudEvent {
	id, _ := payload["id"].(string)
	if id == "" {
		id = uuid.NewString()
	}
	b, err := json.Marshal(payload)
	if err != nil {
		panic(err) // payloads are built from plain maps; cannot fail
	}
	return &cepb.CloudEvent{
		Id:          id,
		Source:      "smoke-compute",
		SpecVersion: "1.0",
		Type:        typ,
		Data:        &cepb.CloudEvent_TextData{TextData: string(b)},
	}
}
