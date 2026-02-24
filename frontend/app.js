const { useState, useEffect, useMemo } = React;

const API_BASE = window.API_BASE || "http://localhost:4000";

function apiClient(token) {
  const instance = axios.create({ baseURL: API_BASE, withCredentials: true });
  if (token)
    instance.defaults.headers.common["Authorization"] = `Bearer ${token}`;
  return instance;
}

function Login({ onSuccess }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      const res = await axios.post(
        `${API_BASE}/admin/login`,
        { email, password },
        { withCredentials: true },
      );
      const token = res.data?.token;
      if (token) localStorage.setItem("token", token);
      onSuccess(token);
    } catch (err) {
      const status = err.response?.status;
      const msg =
        err.response?.data?.message ||
        (status === 401 ? "Email atau password salah" : "Gagal login");
      setError(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="card login-card">
      <h2>Chat Admin</h2>
      <p className="muted">Masuk untuk mengelola tiket chat.</p>
      {error && <div className="alert error">{error}</div>}
      <form onSubmit={handleSubmit}>
        <label>Email</label>
        <input
          className="input"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <label style={{ marginTop: 10 }}>Password</label>
        <input
          className="input"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        <button
          className="button"
          style={{ width: "100%", marginTop: 14 }}
          disabled={loading}
        >
          {loading ? "Masuk..." : "Masuk"}
        </button>
      </form>
    </div>
  );
}

function TicketList({ tickets, activeId, onSelect }) {
  return (
    <div className="ticket-list">
      {tickets.map((t) => (
        <div
          key={t.id}
          className={`ticket-item ${activeId === t.id ? "active" : ""}`}
          onClick={() => onSelect(t)}
        >
          <div className="ticket-title">
            {t.user_name || "Pengguna"} | {t.user_email || ""}
          </div>
          <div className="ticket-meta">
            {t.topic} · {t.competitionTitle || "Tanpa Kompetisi"}
          </div>
          <div className="ticket-meta">{t.summary}</div>
          <div
            className="row"
            style={{ justifyContent: "space-between", marginTop: 6 }}
          >
            <span className="ticket-meta">
              Pesan terakhir: {t.lastMessage || "-"}
            </span>
            <span className={`tag ${t.status === "Proses" ? "warning" : ""}`}>
              {t.status}
            </span>
          </div>
          <div className="row" style={{ marginTop: 6 }}>
            {t.competitionLocationType && (
              <span className="pill pill-ghost">
                {t.competitionLocationType === "online"
                  ? "Kompetisi Online"
                  : "Kompetisi Offline"}
              </span>
            )}
            {t.topic && <span className="pill pill-ghost">{t.topic}</span>}
          </div>
        </div>
      ))}
    </div>
  );
}

function ChatPanel({ ticket, messages, onSend, sending, onRefresh, totalTickets }) {
  const [text, setText] = useState("");
  const listRef = React.useRef(null);
  useEffect(() => setText(""), [ticket?.id]);

  const entries = useMemo(() => buildMessageEntries(messages), [messages]);

  // auto-scroll to bottom when switching ticket or new messages
  useEffect(() => {
    const node = listRef.current;
    if (!node) return;
    node.scrollTo({ top: node.scrollHeight, behavior: "smooth" });
  }, [messages, ticket?.id]);

  if (!ticket)
    return <div className="empty">Pilih tiket untuk melihat percakapan</div>;
  const statusClass = (ticket.status || "").toLowerCase();
  return (
    <div className="content">
      <div className="toolbar">
        <div>
          <div className="title">Chat Admin</div>
          <div className="muted">Total tiket: {totalTickets}</div>
        </div>
        <div className="row" style={{ gap: 8 }}>
          <button className="chip ghost" onClick={onRefresh}>
            Refresh
          </button>
          <button className="chip strong" onClick={() => {}}>
            Broadcast / Reminder
          </button>
        </div>
      </div>
      <div className="row header-cards">
        <div className="user-card">
          <div className="avatar">{(ticket.user_name || "?")[0]}</div>
          <div>
            <div className="title">{ticket.user_name || "Pengguna"}</div>
            <div className="muted row tight">
              <span className="meta-icon">@</span>
              <span>{ticket.user_email || "-"}</span>
            </div>
            {ticket.whatsapp && (
              <div className="muted row tight">
                <span className="meta-icon">☎</span>
                <span>{ticket.whatsapp}</span>
              </div>
            )}
          </div>
        </div>
        <div className="competition-card">
          <div className="title">
            {ticket.competitionTitle || "Tanpa Kompetisi"}
          </div>
          <div className="muted">Perihal: {ticket.topic || "-"}</div>
          <div className="row" style={{ gap: 6, marginTop: 6 }}>
            <span className={`chip-lite ${statusClass}`}>
              {ticket.status}
            </span>
            {ticket.competitionLocationType && (
              <span className="chip-lite ghost">
                {ticket.competitionLocationType === "online"
                  ? "Kompetisi Online"
                  : "Kompetisi Offline"}
              </span>
            )}
          </div>
        </div>
      </div>
      <div className="messages-pane" ref={listRef}>
        {entries.map((entry) =>
          entry.type === "date" ? (
            <div key={`d-${entry.label}`} className="date-divider">
              <span>{entry.label}</span>
            </div>
          ) : (
            <div
              key={entry.message.id}
              className={`message-row ${entry.message.senderType === "admin" ? "me" : "them"}`}
            >
              <div
                className={`chat-bubble ${entry.message.senderType === "admin" ? "me" : "them"}`}
              >
                <div>{entry.message.text}</div>
                <div className="bubble-meta">
                  {formatTime(entry.message.createdAt)}
                </div>
              </div>
            </div>
          )
        )}
      </div>
      <div>
        <textarea
          placeholder="Tulis balasan ke user..."
          value={text}
          onChange={(e) => setText(e.target.value)}
        />
        <div className="row" style={{ justifyContent: "space-between", marginTop: 8 }}>
          <div className="muted" style={{ fontSize: 12 }}>Kirim sebagai admin</div>
          <button
            className="button"
            disabled={sending || !text.trim()}
            onClick={() => {
              onSend(text.trim());
              setText("");
            }}
          >
            Kirim
          </button>
        </div>
      </div>
    </div>
  );
}

function Dashboard({ token }) {
  const [tickets, setTickets] = useState([]);
  const [active, setActive] = useState(null);
  const [messages, setMessages] = useState([]);
  const [sending, setSending] = useState(false);
  const [socket, setSocket] = useState(null);
  const [error, setError] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [compTypeFilter, setCompTypeFilter] = useState("all");
  const [topicFilter, setTopicFilter] = useState("all");

  const api = useMemo(() => apiClient(token), [token]);

  // init socket once
 useEffect(() => {
   const ioClient = window.io?.default || window.io;
   if (!ioClient) {
     setError("socket.io client tidak ter-load");
     return;
   }
   const s = ioClient(API_BASE, {
     transports: ["websocket"],
     auth: token ? { token } : {},
     extraHeaders: token ? { Authorization: `Bearer ${token}` } : {},
   });
   s.on("connect_error", (err) => setError(`Socket error: ${err.message}`));
    s.on("message:new", (m) => {
      const ticketId = m.ticket_id || m.ticketId;
      setMessages((prev) => {
        if (!(active && ticketId === active.id)) return prev;
        if (m.id && prev.some((x) => x.id === m.id)) return prev;
        // jika server tidak kirim id, pakai signature text+createdAt untuk cegah duplikasi
        const sig = `${m.text}-${m.createdAt || ""}-${m.senderType || ""}`;
        if (!m.id && prev.some((x) => `${x.text}-${x.createdAt || ""}-${x.senderType || ""}` === sig)) return prev;
        return [...prev, m];
      });
     setTickets((prev) =>
       prev.map((t) =>
         t.id === ticketId
           ? { ...t, lastMessage: m.text, lastMessageAt: m.createdAt }
           : t,
        ),
      );
    });
    setSocket(s);
    return () => s.disconnect();
  }, [token, active?.id]);

  const loadTickets = async (opts = {}) => {
    const params = {};
    if (statusFilter !== "all") params.status = statusFilter;
    if (compTypeFilter !== "all") params.competition_type = compTypeFilter;
    if (topicFilter !== "all") params.topic = topicFilter;
    try {
      const res = await api.get("/api/admin/chat/tickets", { params });
      const list = res.data.tickets || [];
      setTickets(list);
      if (!active && list.length) {
        setActive(list[0]);
      } else if (active && list.every((t) => t.id !== active.id)) {
        setActive(list[0] || null);
      }
    } catch (e) {
      setError("Gagal memuat tiket");
    }
  };

  const loadMessages = async (ticketId) => {
    try {
      const res = await api.get(`/api/chat/tickets/${ticketId}/messages`);
      setMessages(res.data.messages || []);
      socket?.emit("join-ticket", ticketId);
    } catch (e) {
      setError("Gagal memuat pesan");
    }
  };

  useEffect(() => {
    loadTickets();
  }, []);

  useEffect(() => {
    loadTickets();
  }, [statusFilter, compTypeFilter, topicFilter]);
  useEffect(() => {
    if (active) loadMessages(active.id);
  }, [active?.id]);

  const handleSend = async (text) => {
    if (!active) return;
    setSending(true);
   try {
      // simpan via REST supaya pasti tercatat, server kirim id unik
      const res = await api.post(`/api/chat/tickets/${active.id}/messages`, { text });
      const saved = res.data?.message;
      // kirim socket untuk klien lain jika konek (server akan broadcast, tapi client akan dedup by id)
      if (socket?.connected) {
        socket.emit("message:send", { ticketId: active.id, text });
      }
      // tambahkan langsung pesan yang baru disimpan, dedup dengan id
      if (saved?.id) {
        setMessages((prev) => {
          if (prev.some((m) => m.id === saved.id)) return prev;
          return [...prev, saved];
        });
      } else {
        await loadMessages(active.id);
      }
      setTickets((prev) =>
        prev.map((t) =>
          t.id === active.id
            ? { ...t, lastMessage: text, lastMessageAt: new Date().toISOString() }
            : t
        )
      );
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="layout">
      <div className="sidebar">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <h3 style={{ margin: 0 }}>Chat Admin</h3>
            <div className="muted">Kelola tiket chat</div>
          </div>
          <button className="chip ghost" onClick={() => loadTickets()}>
            Refresh
          </button>
        </div>
        {error && <div className="alert error">{error}</div>}
        <div className="filter-group">
          <div className="filter-label">Status</div>
          <div className="row">
            {["all", "Baru", "Proses", "Selesai"].map((s) => (
              <button
                key={s}
                className={`chip ${statusFilter === s ? "chip-active" : "chip-ghost"}`}
                onClick={() => setStatusFilter(s)}
              >
                {s === "all" ? "Semua" : s}
              </button>
            ))}
          </div>
          <div className="filter-label">Kompetisi</div>
          <div className="row">
            {[
              { key: "all", label: "Semua" },
              { key: "online", label: "Kompetisi Online" },
              { key: "offline", label: "Kompetisi Offline" },
            ].map((c) => (
              <button
                key={c.key}
                className={`chip ${compTypeFilter === c.key ? "chip-active" : "chip-ghost"}`}
                onClick={() => setCompTypeFilter(c.key)}
              >
                {c.label}
              </button>
            ))}
          </div>
          <div className="filter-label">Perihal</div>
          <select
            className="input"
            value={topicFilter}
            onChange={(e) => setTopicFilter(e.target.value)}
          >
            <option value="all">Semua</option>
            <option value="Pendaftaran">Pendaftaran</option>
            <option value="Pemesanan">Pemesanan</option>
            <option value="Lainnya">Lainnya</option>
          </select>
        </div>
        <TicketList
          tickets={tickets}
          activeId={active?.id}
          onSelect={(t) => setActive(t)}
        />
      </div>
      <ChatPanel
        ticket={active}
        messages={messages}
        onSend={handleSend}
        sending={sending}
        onRefresh={() => loadTickets()}
        totalTickets={tickets.length}
      />
    </div>
  );
}

function App() {
  const [token, setToken] = useState(localStorage.getItem("token"));
  return token ? <Dashboard token={token} /> : <Login onSuccess={setToken} />;
}

const rootEl = document.getElementById("root");
const root = ReactDOM.createRoot
  ? ReactDOM.createRoot(rootEl)
  : { render: (comp) => ReactDOM.render(comp, rootEl) };
root.render(<App />);

// helpers
function buildMessageEntries(msgs = []) {
  const out = [];
  let lastLabel = "";
  msgs.forEach((m) => {
    const label = friendlyDateLabel(m.createdAt);
    if (label && label !== lastLabel) {
      out.push({ type: "date", label });
      lastLabel = label;
    }
    out.push({ type: "msg", message: m });
  });
  return out;
}

function friendlyDateLabel(raw) {
  const dt = new Date(raw);
  if (Number.isNaN(dt)) return null;
  const today = new Date();
  const d0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const d1 = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate());
  const diff = (d1 - d0) / (1000 * 60 * 60 * 24);
  if (diff === 0) return "Hari ini";
  if (diff === -1) return "Kemarin";
  const months = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"];
  return `${d1.getDate().toString().padStart(2, "0")} ${months[d1.getMonth()]} ${d1.getFullYear()}`;
}

function formatTime(raw) {
  const dt = new Date(raw);
  if (Number.isNaN(dt)) return raw || "";
  const hh = dt.getHours().toString().padStart(2, "0");
  const mm = dt.getMinutes().toString().padStart(2, "0");
  return `${hh}:${mm}`;
}
