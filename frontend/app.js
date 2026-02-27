const { useState, useEffect, useMemo } = React;

const API_BASE = window.API_BASE || "http://localhost:4000";
const ROUTES = {
  LOGIN: "#/login",
  USER: "#/user",
  DASHBOARD: "#/dashboard",
};

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
    <div className="login-wrapper">
      <div className="bg-shapes">
        <div className="shape circle" />
        <div className="shape square" />
        <div className="shape triangle" />
        <div className="shape triangle alt" />
        <div className="shape circle" />
        <div className="shape square" />
      </div>
      <div className="card login-card">
        <div className="login-badge">
          <span className="dot" />
          <span>POSI Admin Portal</span>
        </div>
        <h2 style={{ marginBottom: 8 }}>Selamat Datang</h2>
        <p className="muted" style={{ marginTop: 0, marginBottom: 18 }}>
          Masuk untuk mengelola tiket chat dan membalas pengguna.
        </p>
        {error && <div className="alert error">{error}</div>}
        <form onSubmit={handleSubmit}>
          <label className="muted" style={{ color: "#0f172a", fontWeight: 600 }}>
            Email
          </label>
          <div className="input-group">
            <span className="input-icon" aria-hidden>📧</span>
            <input
              className="input input-with-icon"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <label
            style={{ marginTop: 12, color: "#0f172a", fontWeight: 600 }}
            className="muted"
          >
            Password
          </label>
          <div className="input-group">
            <span className="input-icon" aria-hidden>🔒</span>
            <input
              className="input input-with-icon"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
        </div>
        <button
          className="button"
          style={{ width: "100%", marginTop: 18, display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 8, fontSize: 16, padding: "14px 18px" }}
          disabled={loading}
        >
          <span aria-hidden>🚀</span>
          {loading ? "Memeriksa..." : "Masuk ke Dashboard"}
        </button>
      </form>
        <p className="muted" style={{ fontSize: 12, marginTop: 14, lineHeight: 1.5 }}>
          Pastikan Anda menggunakan jaringan terpercaya dan jangan bagikan kredensial kepada
          siapa pun.
        </p>
      </div>
    </div>
  );
}

function RoleSelect({ onPick, onLogout }) {
  const roles = [
    {
      key: "admin-pendaftaran",
      title: "Masuk Sebagai Admin Pendaftaran Kompetisi Online",
      description: "Kelola tiket bertopik pendaftaran untuk kompetisi online.",
      competitionType: "online",
      topic: "Pendaftaran",
    },
    {
      key: "admin-pemesanan",
      title: "Masuk Sebagai Admin Pemesanan Kompetisi Online",
      description: "Tangani tiket pemesanan untuk kompetisi online.",
      competitionType: "online",
      topic: "Pemesanan",
    },
    {
      key: "admin-offline",
      title: "Masuk Sebagai Admin Kompetisi Offline",
      description: "Fokus pada tiket kompetisi offline.",
      competitionType: "offline",
      topic: "all",
    },
    {
      key: "superadmin",
      title: "Masuk Sebagai Superadmin",
      description: "Lihat semua tiket tanpa filter.",
      competitionType: "all",
      topic: "all",
    },
  ];

  return (
    <div className="role-wrapper">
      <div className="bg-shapes">
        <div className="shape circle" />
        <div className="shape square" />
        <div className="shape triangle" />
        <div className="shape triangle alt" />
        <div className="shape circle" />
        <div className="shape square" />
      </div>
      <div className="role-hero">
        <div>
          <div className="title" style={{ fontSize: 22, marginBottom: 6 }}>Pilih Peran</div>
          <div className="muted" style={{ fontSize: 14 }}>
            Masuk sesuai jenis admin. Superadmin melihat semua tiket.
          </div>
        </div>
        <button className="chip ghost" onClick={onLogout}>
          Logout
        </button>
      </div>
      <div className="role-grid">
        {roles.map((role) => (
          <div
            key={role.key}
            className="card role-card"
            onClick={() => onPick(role)}
          >
            <div className="role-icon" aria-hidden>
              {role.key === "admin-pendaftaran" && "📝"}
              {role.key === "admin-pemesanan" && "🛒"}
              {role.key === "admin-offline" && "📍"}
              {role.key === "superadmin" && "⭐"}
            </div>
            <div>
              <h3 style={{ margin: "0 0 8px 0" }}>{role.title}</h3>
              <p className="muted" style={{ margin: 0 }}>{role.description}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function TicketList({ tickets, activeId, onSelect, role }) {
  return (
    <div className="ticket-list">
      {tickets.map((t) => (
        <div
          key={t.id}
          className={`ticket-card ${activeId === t.id ? "active" : ""}`}
          onClick={() => onSelect(t)}
        >
          <div className="ticket-avatar">{(t.user_name || "?")[0]}</div>
          <div className="ticket-info">
            <div className="row" style={{ justifyContent: "space-between", alignItems: "flex-start" }}>
              <div className="ticket-name truncate">{t.user_name || "Pengguna"}</div>
              <span
                className={`tag ${t.status === "Proses" ? "warning" : ""} ${
                  t.status === "Selesai" ? "success" : ""
                }`}
              >
                {t.status}
              </span>
            </div>
            <div className="ticket-email truncate">{t.user_email || "-"}</div>
            <div className="ticket-line truncate">
              {(t.topic && `${t.topic}`) || "Tanpa Perihal"} · {t.competitionTitle || "Tanpa Kompetisi"}
            </div>
            <div className="ticket-summary truncate">
              {t.lastMessage || t.summary || "-"}
            </div>
            <div className="row" style={{ marginTop: 6, gap: 6 }}>
              {(t.competitionLocationType || role?.competitionType) && (
                <span className="pill pill-ghost">
                  {(t.competitionLocationType || role?.competitionType) === "online"
                    ? "Kompetisi Online"
                    : (t.competitionLocationType || role?.competitionType)}
                </span>
              )}
              {(t.topic || role?.topic) && <span className="pill pill-ghost">{t.topic || role?.topic}</span>}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function ChatPanel({ ticket, messages, onSend, onStatusChange, sending, onRefresh, totalTickets, socketConnected }) {
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
          <div className="muted row tight">
            <span className={`status-dot ${socketConnected ? "on" : "off"}`} />
            <span>{socketConnected ? "Terhubung" : "Menyambung..."}</span>
            <span>· Total tiket: {totalTickets}</span>
          </div>
        </div>
        <div className="row" style={{ gap: 8 }}>
          <button className="chip ghost" onClick={onRefresh}>
            🔄 Refresh
          </button>
          <button className="chip strong" onClick={() => {}}>
            📢 Broadcast / Reminder
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
            <div className="status-radio">
              {[
                { key: "Baru", label: "Baru", color: "blue" },
                { key: "Proses", label: "Proses", color: "yellow" },
                { key: "Selesai", label: "Selesai", color: "green" },
              ].map((s) => (
                <button
                  key={s.key}
                  className={`status-pill ${s.color} ${ticket.status === s.key ? "active" : ""}`}
                  onClick={() => onStatusChange?.(s.key)}
                >
                  {s.label}
                </button>
              ))}
            </div>
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
      <div className="send-box">
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
            📤 Kirim
          </button>
        </div>
      </div>
    </div>
  );
}

function Dashboard({ token, role, onBack, onLogout }) {
  const [tickets, setTickets] = useState([]);
  const [active, setActive] = useState(null);
  const [search, setSearch] = useState("");
  const [messages, setMessages] = useState([]);
  const [sending, setSending] = useState(false);
  const [socket, setSocket] = useState(null);
  const [socketConnected, setSocketConnected] = useState(false);
  const [error, setError] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");

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
   s.on("connect", () => {
     setSocketConnected(true);
     if (active?.id) s.emit("join-ticket", active.id);
   });
    s.on("disconnect", () => setSocketConnected(false));
   s.on("message:new", (m) => {
     const ticketId = m.ticket_id || m.ticketId;
      setMessages((prev) => {
        if (!(active && ticketId === active.id)) return prev;
        if (m.id && prev.some((x) => x.id === m.id)) return prev;
        const sig = `${m.text}-${m.createdAt || ""}-${m.senderType || ""}`;
        if (!m.id && prev.some((x) => `${x.text}-${x.createdAt || ""}-${x.senderType || ""}` === sig)) return prev;
        return [...prev, m];
      });
      setTickets((prev) =>
        prev.map((t) =>
          t.id === ticketId
            ? { ...t, lastMessage: m.text, lastMessageAt: m.createdAt }
            : t
        )
      );
    });
    setSocket(s);
    return () => s.disconnect();
  }, [token, active?.id]);

  const loadTickets = async () => {
    const params = {};
    if (statusFilter !== "all") params.status = statusFilter;
    if (search.trim()) params.q = search.trim();
    try {
      const res = await api.get("/api/admin/chat/tickets", {
        params: { ...params, _ts: Date.now() },
        headers: { "Cache-Control": "no-cache" },
      });
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
  }, [statusFilter, search, role?.competitionType, role?.topic]);
  useEffect(() => {
    if (active) {
      loadMessages(active.id);
      if (socket?.connected) socket.emit("join-ticket", active.id);
    }
  }, [active?.id]);

  const handleSend = async (text) => {
    if (!active) return;
    setSending(true);
   try {
      // kirim via endpoint admin; fallback ke user endpoint jika gagal (compat)
      let saved;
      try {
        const res = await api.post(`/api/admin/chat/tickets/${active.id}/messages`, { text });
        saved = res.data?.message;
      } catch (_) {
        const res = await api.post(`/api/chat/tickets/${active.id}/messages`, { text });
        saved = res.data?.message;
      }
      // pesan sudah disimpan via REST; server akan broadcast message:new.
      // Optimistik: tambahkan jika belum ada.
      const optimistic =
        saved ||
        {
          id: Date.now(),
          ticketId: active.id,
          senderType: "admin",
          text,
          createdAt: new Date().toISOString(),
        };
      setMessages((prev) => {
        if (optimistic.id && prev.some((m) => m.id === optimistic.id)) return prev;
        return [...prev, optimistic];
      });
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

  const handleStatusChange = async (status) => {
    if (!active) return;
    try {
      await api.patch(`/api/admin/chat/tickets/${active.id}/status`, { status });
      setActive((prev) => (prev ? { ...prev, status } : prev));
      setTickets((prev) =>
        prev.map((t) => (t.id === active.id ? { ...t, status } : t))
      );
    } catch (e) {
      setError("Gagal mengubah status");
    }
  };

  return (
    <div className="layout">
      <div className="sidebar">
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <h3 style={{ margin: 0 }}>{role.title}</h3>
          </div>
          <div className="row" style={{ gap: 6 }}>
            <button className="chip ghost" onClick={onBack}>
              Ganti Peran
            </button>
            <button className="chip ghost" onClick={onLogout}>
              Logout
            </button>
          </div>
        </div>
        {error && <div className="alert error">{error}</div>}
        <div className="search-box">
          <input
            className="input"
            placeholder="Cari nama / email / identitas..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <button className="chip ghost" onClick={() => loadTickets()}>🔍 Cari</button>
        </div>
        <div className="filter-group">
          <div className="filter-label">📊 Status</div>
          <div className="row status-row">
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
        </div>
        <TicketList
          tickets={tickets}
          activeId={active?.id}
          onSelect={(t) => setActive(t)}
          role={role}
        />
      </div>
      <ChatPanel
        ticket={active}
        messages={messages}
        onSend={handleSend}
        onStatusChange={handleStatusChange}
        sending={sending}
        onRefresh={() => loadTickets()}
        totalTickets={tickets.length}
        socketConnected={socketConnected}
      />
    </div>
  );
}

function App() {
  const [token, setToken] = useState(localStorage.getItem("token"));
  const [route, setRoute] = useState(window.location.hash || (token ? ROUTES.USER : ROUTES.LOGIN));
  const [selectedRole, setSelectedRole] = useState(() => {
    try {
      const saved = localStorage.getItem("selectedRole");
      return saved ? JSON.parse(saved) : null;
    } catch (_) {
      return null;
    }
  });

  useEffect(() => {
    const handler = () => setRoute(window.location.hash || ROUTES.LOGIN);
    window.addEventListener("hashchange", handler);
    return () => window.removeEventListener("hashchange", handler);
  }, []);

  useEffect(() => {
    if (!selectedRole && route === ROUTES.DASHBOARD) {
      navigate(ROUTES.USER);
    }
  }, [selectedRole, route]);

  const navigate = (hash) => {
    if (window.location.hash === hash) {
      setRoute(hash);
    } else {
      window.location.hash = hash;
    }
  };

  const logout = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("selectedRole");
    setToken(null);
    setSelectedRole(null);
    navigate(ROUTES.LOGIN);
  };

  useEffect(() => {
    if (!token && route !== ROUTES.LOGIN) {
      navigate(ROUTES.LOGIN);
    }
  }, [token, route]);

  if (!token) {
    return <Login onSuccess={(tok) => { setToken(tok); navigate(ROUTES.USER); }} />;
  }

  const ensureRole = (role) => {
    setSelectedRole(role);
    localStorage.setItem("selectedRole", JSON.stringify(role));
  };

  if (route === ROUTES.USER || !selectedRole) {
    return (
      <RoleSelect
        onPick={(role) => {
          ensureRole(role);
          navigate(ROUTES.DASHBOARD);
        }}
        onLogout={logout}
      />
    );
  }

  if (route === ROUTES.DASHBOARD) {
    return (
      <Dashboard
        token={token}
        role={selectedRole}
        onBack={() => navigate(ROUTES.USER)}
        onLogout={logout}
      />
    );
  }

  // default: login
  return <Login onSuccess={(tok) => { setToken(tok); navigate(ROUTES.USER); }} />;
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
