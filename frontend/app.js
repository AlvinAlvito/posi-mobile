const { useState, useEffect, useMemo } = React;

const API_BASE = window.API_BASE || 'http://localhost:4000';

function apiClient(token) {
  const instance = axios.create({
    baseURL: API_BASE,
    withCredentials: true,
  });
  if (token) instance.defaults.headers.common['Authorization'] = `Bearer ${token}`;
  return instance;
}

function Login({ onSuccess }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const res = await axios.post(`${API_BASE}/admin/login`, { email, password }, { withCredentials: true });
      const token = res.data?.token;
      if (token) localStorage.setItem('token', token);
      onSuccess(token);
    } catch (err) {
      const status = err.response?.status;
      const msg = err.response?.data?.message || (status === 401 ? 'Email atau password salah' : 'Gagal login');
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
        <input className="input" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        <label style={{ marginTop: 10 }}>Password</label>
        <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        <button className="button" style={{ width: '100%', marginTop: 14 }} disabled={loading}>
          {loading ? 'Masuk...' : 'Masuk'}
        </button>
      </form>
    </div>
  );
}

function TicketList({ tickets, activeId, onSelect }) {
  return (
    <div className="ticket-list">
      {tickets.map((t) => (
        <div key={t.id} className={`ticket-item ${activeId === t.id ? 'active' : ''}`} onClick={() => onSelect(t)}>
          <div className="ticket-title">{t.user_name || 'Pengguna'} | {t.user_email || ''}</div>
          <div className="ticket-meta">{t.topic} · {t.competitionTitle || 'Tanpa Kompetisi'}</div>
          <div className="ticket-meta">{t.summary}</div>
          <div className="row" style={{ justifyContent: 'space-between', marginTop: 6 }}>
            <span className="ticket-meta">Pesan terakhir: {t.lastMessage || '-'}</span>
            <span className="tag {t.status==='Proses'?'warning':''}">{t.status}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

function ChatPanel({ ticket, messages, onSend, sending }) {
  const [text, setText] = useState('');
  useEffect(() => setText(''), [ticket?.id]);

  if (!ticket) return <div className="empty">Pilih tiket untuk melihat percakapan</div>;
  return (
    <div className="content">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div>
          <div className="title">{ticket.user_name || 'Pengguna'}</div>
          <div className="muted">{ticket.user_email || ''}</div>
          {ticket.whatsapp && <div className="muted">{ticket.whatsapp}</div>}
        </div>
        <div className="row" style={{ gap: 6 }}>
          <span className="tag">{ticket.competitionTitle || 'Tanpa Kompetisi'}</span>
          <span className="tag warning">{ticket.status}</span>
        </div>
      </div>
      <div style={{ overflowY: 'auto', paddingRight: 8 }}>
        {messages.map((m) => (
          <div key={m.id} className={`chat-bubble ${m.senderType === 'admin' ? 'me' : 'them'}`}>
            <div>{m.text}</div>
            <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>{m.createdAt?.slice(0,16)}</div>
          </div>
        ))}
      </div>
      <div>
        <textarea placeholder="Tulis balasan ke user..." value={text} onChange={(e) => setText(e.target.value)} />
        <button className="button" style={{ float: 'right', marginTop: 8 }} disabled={sending || !text.trim()} onClick={() => { onSend(text.trim()); setText(''); }}>Kirim</button>
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

  const api = useMemo(() => apiClient(token), [token]);

  useEffect(() => {
    const io = window.io;
    const s = io(API_BASE, {
      transports: ['websocket'],
      extraHeaders: token ? { Authorization: `Bearer ${token}` } : {},
    });
    s.on('connect', () => console.log('socket connected'));
    s.on('message:new', (m) => {
      setMessages((prev) => (active && m.ticket_id === active.id ? [...prev, m] : prev));
      setTickets((prev) => prev.map((t) => (t.id === m.ticket_id ? { ...t, lastMessage: m.text, lastMessageAt: m.createdAt } : t)));
    });
    setSocket(s);
    return () => s.disconnect();
  }, [token, active?.id]);

  const loadTickets = async () => {
    const res = await api.get('/admin/chat/tickets');
    setTickets(res.data.tickets || []);
    if (!active && res.data.tickets?.length) setActive(res.data.tickets[0]);
  };

  const loadMessages = async (ticketId) => {
    const res = await api.get(`/api/chat/tickets/${ticketId}/messages`);
    setMessages(res.data.messages || []);
    if (socket) socket.emit('join-ticket', ticketId);
  };

  useEffect(() => { loadTickets(); }, []);
  useEffect(() => { if (active) loadMessages(active.id); }, [active?.id]);

  const handleSend = async (text) => {
    if (!active) return;
    setSending(true);
    try {
      socket?.emit('message:send', { ticketId: active.id, text });
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="layout">
      <div className="sidebar">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <div>
            <h3 style={{ margin: 0 }}>Chat Admin</h3>
            <div className="muted">Kelola tiket chat</div>
          </div>
          <button className="chip" onClick={loadTickets}>Refresh</button>
        </div>
        <TicketList tickets={tickets} activeId={active?.id} onSelect={(t) => setActive(t)} />
      </div>
      <ChatPanel ticket={active} messages={messages} onSend={handleSend} sending={sending} />
    </div>
  );
}

function App() {
  const [token, setToken] = useState(localStorage.getItem('token'));
  return token ? <Dashboard token={token} /> : <Login onSuccess={setToken} />;
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
