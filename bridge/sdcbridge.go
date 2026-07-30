// sdcbridge – Hintergrund-App für den SDC-Editor von LrMediaWiki2.
//
// WOZU DAS GANZE
//
// Der Editor ist eine einzelne HTML-Seite. Solange Lightroom sie als
// file:///… im Browser öffnet, kann die Seite nicht mit Lightroom reden:
// ein fetch von file:// auf 127.0.0.1 wurde auf Haralds Windows-Rechner
// blockiert, und LrSocket kann keine Antwort ausliefern, die eine Seite
// verwerten könnte (es quittiert jede empfangene Zeile mit "ok").
//
// Dieses Programm liefert die Seite selbst aus. Damit laufen Seite und
// Schnittstelle unter derselben Herkunft (http://127.0.0.1:PORT), und
// fetch sowie Server-Sent-Events funktionieren ohne CORS und ohne
// Private-Network-Frage – eine Same-Origin-Anfrage ist gar keine
// Cross-Origin-Anfrage.
//
// Lightroom braucht dadurch überhaupt keinen lauschenden Socket mehr.
// Es redet nur ausgehend, und zwar über einen einzigen Endpunkt:
//
//	POST /sync   – schickt den Zustand des aktuellen Fotos hin und holt
//	               in derselben Antwort ein wartendes Ergebnis ab.
//	               Zählt gleichzeitig als Lebenszeichen.
//
// Der Browser benutzt:
//
//	GET  /        – die Editorseite
//	GET  /state   – Zustand des aktuellen Fotos
//	GET  /events  – Server-Sent-Events, meldet Fotowechsel
//	POST /result  – das Bearbeitungsergebnis
//
// SICHERHEIT
//
// Der Server lauscht ausschließlich auf 127.0.0.1, niemals auf allen
// Schnittstellen. Jede Anfrage muss ein Sitzungstoken mitbringen, das
// Lightroom bei jedem Start neu erzeugt; ohne Token gibt es 403. Der
// Host-Kopf muss auf 127.0.0.1 oder localhost lauten, damit eine
// fremde Webseite den Dienst nicht per DNS-Rebinding erreichen kann.
// Ohne Lebenszeichen von Lightroom beendet sich der Server selbst –
// es gibt im Lightroom-SDK keinen Aufhänger für das Entladen eines
// Zusatzmoduls, also kann Lightroom das Beenden nicht zuverlässig
// selbst veranlassen.
//
// Die Editorseite wird NICHT ins Programm einkompiliert, sondern bei
// jeder Anfrage frisch von --page gelesen. So bleibt
// SdcEditorTemplate.lua die einzige Quelle der Seite, und eine
// Änderung an der Seite verlangt keinen neuen Programmbau.
package main

import (
	"crypto/subtle"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const version = "1.0.0"

// ---------------------------------------------------------------------------
// Zustand
// ---------------------------------------------------------------------------

type bridge struct {
	mu sync.Mutex

	token    string
	pagePath string

	// Zustand des aktuellen Fotos, wie Lightroom ihn geschickt hat.
	// Bewusst als RawMessage: der Server interessiert sich nicht für den
	// Inhalt und soll ihn auch nicht umformen.
	state json.RawMessage
	rev   int64

	// Ergebnis aus dem Browser, das auf Abholung durch Lightroom wartet.
	result json.RawMessage

	lastContact time.Time

	// Offene Server-Sent-Events-Verbindungen.
	subs map[chan []byte]struct{}
}

func newBridge(token, pagePath string) *bridge {
	return &bridge{
		token:       token,
		pagePath:    pagePath,
		lastContact: time.Now(),
		subs:        make(map[chan []byte]struct{}),
	}
}

// setState übernimmt einen neuen Zustand und benachrichtigt alle offenen
// Ereignisströme. Gibt zurück, ob sich etwas geändert hat.
func (b *bridge) setState(s json.RawMessage) bool {
	b.mu.Lock()
	if string(b.state) == string(s) {
		b.lastContact = time.Now()
		b.mu.Unlock()
		return false
	}
	b.state = s
	b.rev++
	b.lastContact = time.Now()
	msg := b.envelopeLocked()
	subs := make([]chan []byte, 0, len(b.subs))
	for ch := range b.subs {
		subs = append(subs, ch)
	}
	b.mu.Unlock()

	for _, ch := range subs {
		// Nicht blockieren: ein hängender Empfänger darf den Rest nicht
		// aufhalten. Wer nicht mitkommt, holt sich den Zustand beim
		// nächsten Ereignis oder per GET /state.
		select {
		case ch <- msg:
		default:
		}
	}
	return true
}

// envelopeLocked baut die Nutzlast für /state und /events. Aufrufer muss
// die Sperre halten.
func (b *bridge) envelopeLocked() []byte {
	st := b.state
	if len(st) == 0 {
		st = json.RawMessage("null")
	}
	out := fmt.Sprintf(`{"rev":%d,"state":%s}`, b.rev, st)
	return []byte(out)
}

func (b *bridge) snapshot() []byte {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.envelopeLocked()
}

func (b *bridge) putResult(r json.RawMessage) {
	b.mu.Lock()
	b.result = r
	b.mu.Unlock()
}

// takeResult holt ein wartendes Ergebnis ab und löscht es dabei. Ein
// Ergebnis wird also genau einmal ausgeliefert.
func (b *bridge) takeResult() json.RawMessage {
	b.mu.Lock()
	defer b.mu.Unlock()
	r := b.result
	b.result = nil
	b.lastContact = time.Now()
	return r
}

func (b *bridge) touch() {
	b.mu.Lock()
	b.lastContact = time.Now()
	b.mu.Unlock()
}

func (b *bridge) idleFor() time.Duration {
	b.mu.Lock()
	defer b.mu.Unlock()
	return time.Since(b.lastContact)
}

func (b *bridge) subscribe() chan []byte {
	ch := make(chan []byte, 4)
	b.mu.Lock()
	b.subs[ch] = struct{}{}
	b.mu.Unlock()
	return ch
}

func (b *bridge) unsubscribe(ch chan []byte) {
	b.mu.Lock()
	delete(b.subs, ch)
	b.mu.Unlock()
}

// ---------------------------------------------------------------------------
// Zugangsprüfung
// ---------------------------------------------------------------------------

// checkAuth prüft Host-Kopf und Token. Der Host-Kopf-Test schützt gegen
// DNS-Rebinding: eine fremde Seite kann einen Namen auf 127.0.0.1 zeigen
// lassen, aber den Host-Kopf nicht auf 127.0.0.1 fälschen, ohne dass der
// Browser ihn entsprechend setzt.
func (b *bridge) checkAuth(w http.ResponseWriter, r *http.Request) bool {
	host := r.Host
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	host = strings.ToLower(strings.Trim(host, "[]"))
	if host != "127.0.0.1" && host != "localhost" && host != "::1" {
		http.Error(w, "bad host", http.StatusForbidden)
		return false
	}

	got := r.URL.Query().Get("t")
	if got == "" {
		got = r.Header.Get("X-Bridge-Token")
	}
	// Konstante Laufzeit, damit sich das Token nicht Zeichen für Zeichen
	// erraten lässt.
	if subtle.ConstantTimeCompare([]byte(got), []byte(b.token)) != 1 {
		http.Error(w, "forbidden", http.StatusForbidden)
		return false
	}
	return true
}

func noStore(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate")
	w.Header().Set("Pragma", "no-cache")
	// Die Seite darf nicht in einem fremden Rahmen landen.
	w.Header().Set("X-Frame-Options", "DENY")
	w.Header().Set("Referrer-Policy", "no-referrer")
}

// ---------------------------------------------------------------------------
// Endpunkte für den Browser
// ---------------------------------------------------------------------------

func (b *bridge) handlePage(w http.ResponseWriter, r *http.Request) {
	if !b.checkAuth(w, r) {
		return
	}
	data, err := os.ReadFile(b.pagePath)
	if err != nil {
		http.Error(w, "editor page not found: "+err.Error(),
			http.StatusInternalServerError)
		return
	}
	noStore(w)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(data)
}

func (b *bridge) handleState(w http.ResponseWriter, r *http.Request) {
	if !b.checkAuth(w, r) {
		return
	}
	noStore(w)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(b.snapshot())
}

func (b *bridge) handleEvents(w http.ResponseWriter, r *http.Request) {
	if !b.checkAuth(w, r) {
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}

	noStore(w)
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)

	ch := b.subscribe()
	defer b.unsubscribe(ch)

	// Sofort den aktuellen Stand schicken, damit eine neu geladene Seite
	// nicht auf den ersten Fotowechsel warten muss.
	fmt.Fprintf(w, "event: state\ndata: %s\n\n", b.snapshot())
	flusher.Flush()

	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case msg := <-ch:
			fmt.Fprintf(w, "event: state\ndata: %s\n\n", msg)
			flusher.Flush()
		case <-ticker.C:
			// Kommentarzeile als Lebenszeichen, damit Zwischenstationen
			// die Verbindung nicht wegen Untätigkeit schließen.
			fmt.Fprint(w, ": ping\n\n")
			flusher.Flush()
		}
	}
}

func (b *bridge) handleResult(w http.ResponseWriter, r *http.Request) {
	if !b.checkAuth(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	var body json.RawMessage
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<20))
	if err := dec.Decode(&body); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}
	b.putResult(body)
	log.Printf("Ergebnis von der Seite entgegengenommen (%d Bytes) - wartet auf den naechsten /sync", len(body))
	noStore(w)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	fmt.Fprint(w, `{"ok":true}`)
}

// ---------------------------------------------------------------------------
// Endpunkt für Lightroom
// ---------------------------------------------------------------------------

type syncRequest struct {
	// State ist der Zustand des aktuellen Fotos. Fehlt das Feld oder ist
	// es null, bleibt der gespeicherte Zustand unverändert – Lightroom
	// schickt ihn nur bei einem Wechsel mit.
	State json.RawMessage `json:"state"`
}

type syncResponse struct {
	Rev    int64           `json:"rev"`
	Result json.RawMessage `json:"result,omitempty"`
	Subs   int             `json:"subs"`
}

func (b *bridge) handleSync(w http.ResponseWriter, r *http.Request) {
	if !b.checkAuth(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}

	var req syncRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<20))
	if err := dec.Decode(&req); err != nil {
		http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return
	}

	if len(req.State) > 0 && string(req.State) != "null" {
		b.setState(req.State)
	} else {
		b.touch()
	}

	res := b.takeResult()
	if len(res) > 0 {
		log.Printf("Ergebnis an Lightroom uebergeben (%d Bytes)", len(res))
	}

	b.mu.Lock()
	rev := b.rev
	subs := len(b.subs)
	b.mu.Unlock()

	noStore(w)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(w)
	enc.Encode(syncResponse{Rev: rev, Result: res, Subs: subs})
}

func (b *bridge) handleHealth(w http.ResponseWriter, r *http.Request) {
	// Bewusst ohne Token: Lightroom soll prüfen können, ob auf einem Port
	// überhaupt eine Brücke sitzt. Die Antwort verrät nichts.
	noStore(w)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	fmt.Fprintf(w, `{"ok":true,"app":"sdcbridge","version":%q}`, version)
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Protokollierung
//
// Ohne das stand im Protokoll nur die Startzeile, und ein Fehlschlag war von
// aussen nicht zu unterscheiden von "die Anfrage kam nie an". Genau daran hat
// die Fehlersuche zweimal gehangen.
// ---------------------------------------------------------------------------

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(p []byte) (int, error) {
	if s.status == 0 {
		s.status = http.StatusOK
	}
	n, err := s.ResponseWriter.Write(p)
	s.bytes += n
	return n, err
}

// Flush MUSS durchgereicht werden, sonst kommt beim Ereignisstrom nichts mehr
// an: /events haengt daran, dass der ResponseWriter ein http.Flusher ist, und
// eine Verpackung ohne diese Methode nimmt ihm das weg.
func (s *statusRecorder) Flush() {
	if f, ok := s.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func withLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(rec, r)
		if rec.status == 0 {
			rec.status = http.StatusOK
		}
		// /sync kommt einmal pro Sekunde. Erfolgreiche, ereignislose Syncs
		// bleiben stumm, sonst waere das Protokoll nach einer Stunde
		// unbrauchbar. Alles andere wird protokolliert - insbesondere jeder
		// Fehlercode und jedes POST auf /result.
		if r.URL.Path == "/sync" && rec.status == http.StatusOK {
			return
		}
		log.Printf("%s %s -> %d (%d Bytes)", r.Method, r.URL.Path, rec.status, rec.bytes)
	})
}

func main() {
	token := flag.String("token", "", "Sitzungstoken; jede Anfrage muss es mitbringen")
	page := flag.String("page", "", "Pfad zur Editorseite (HTML)")
	portFile := flag.String("portfile", "", "Datei, in die Port und Prozessnummer geschrieben werden")
	logFile := flag.String("log", "", "Protokolldatei (leer = Standardausgabe)")
	idle := flag.Duration("idle", 3*time.Minute,
		"Selbstabschaltung nach dieser Zeit ohne Lebenszeichen von Lightroom")
	showVersion := flag.Bool("version", false, "Version ausgeben und beenden")
	flag.Parse()

	if *showVersion {
		fmt.Println("sdcbridge " + version)
		return
	}
	if *token == "" {
		fmt.Fprintln(os.Stderr, "sdcbridge: --token fehlt")
		os.Exit(2)
	}
	if *page == "" {
		fmt.Fprintln(os.Stderr, "sdcbridge: --page fehlt")
		os.Exit(2)
	}

	if *logFile != "" {
		fh, err := os.OpenFile(*logFile,
			os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
		if err != nil {
			fmt.Fprintln(os.Stderr, "sdcbridge: Protokolldatei: ", err)
		} else {
			defer fh.Close()
			log.SetOutput(fh)
		}
	}
	log.SetFlags(log.Ldate | log.Ltime)

	b := newBridge(*token, *page)

	// Ausschliesslich auf der Rückschleife lauschen. Port 0 heisst: das
	// Betriebssystem sucht einen freien – damit kann es keinen
	// Portkonflikt geben, anders als beim festen OAuth-Port 8128.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatalf("kann nicht lauschen: %v", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	log.Printf("sdcbridge %s gestartet, Port %d, Seite %s", version, port, *page)

	if *portFile != "" {
		// Erst in eine Nebendatei schreiben, dann umbenennen: Lightroom
		// darf niemals eine halb geschriebene Datei lesen.
		tmp := *portFile + ".tmp"
		content := fmt.Sprintf(`{"port":%d,"pid":%d,"version":%q}`+"\n",
			port, os.Getpid(), version)
		if err := os.WriteFile(tmp, []byte(content), 0o600); err != nil {
			log.Fatalf("Portdatei: %v", err)
		}
		if err := os.Rename(tmp, *portFile); err != nil {
			log.Fatalf("Portdatei umbenennen: %v", err)
		}
		// Beim Beenden aufräumen, damit Lightroom keine Brücke vermutet,
		// die es nicht mehr gibt.
		defer os.Remove(*portFile)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		b.handlePage(w, r)
	})
	mux.HandleFunc("/state", b.handleState)
	mux.HandleFunc("/events", b.handleEvents)
	mux.HandleFunc("/result", b.handleResult)
	mux.HandleFunc("/sync", b.handleSync)
	mux.HandleFunc("/health", b.handleHealth)

	srv := &http.Server{
		Handler: withLog(mux),
		// Kein WriteTimeout: der Ereignisstrom bleibt absichtlich offen.
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Selbstabschalter. Es gibt im Lightroom-SDK keinen Aufhänger für das
	// Entladen eines Zusatzmoduls, also kann Lightroom das Beenden nicht
	// zuverlässig veranlassen. Bleiben die Lebenszeichen aus, ist
	// Lightroom weg – dann hat dieser Prozess keinen Zweck mehr.
	go func() {
		tick := time.NewTicker(15 * time.Second)
		defer tick.Stop()
		for range tick.C {
			if d := b.idleFor(); d > *idle {
				log.Printf("kein Lebenszeichen seit %s – beende mich", d.Round(time.Second))
				if *portFile != "" {
					os.Remove(*portFile)
				}
				os.Exit(0)
			}
		}
	}()

	if err := srv.Serve(ln); err != nil {
		log.Printf("Server beendet: %v", err)
	}
}
