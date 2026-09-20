import './App.css'

export default function App() {
  const services = [
    {
      title: "Sovereign AI Chat",
      description: "Access your private conversational interface. Direct dynamic routing to DeepSeek-R1 70B & 14B.",
      url: "https://ai.internal-mesh.local",
      icon: "🌌",
      status: "online",
      glowColor: "rgba(139, 92, 246, 0.2)",
      borderColor: "rgba(139, 92, 246, 0.3)",
      shadowColor: "rgba(139, 92, 246, 0.15)",
      hoverColor: "#c084fc",
      iconBg: "rgba(139, 92, 246, 0.1)"
    },
    {
      title: "Grafana Telemetry",
      description: "Monitor real-time system performance, CPU/RAM, and DCGM GPU metrics for both physical nodes.",
      url: "https://dashboards.internal-mesh.local",
      icon: "📊",
      status: "online",
      glowColor: "rgba(249, 115, 22, 0.2)",
      borderColor: "rgba(249, 115, 22, 0.3)",
      shadowColor: "rgba(249, 115, 22, 0.15)",
      hoverColor: "#ffedd5",
      iconBg: "rgba(249, 115, 22, 0.1)"
    },
    {
      title: "Authentik SSO",
      description: "Manage centralized OIDC client configuration, user access rules, and secure token flows.",
      url: "https://auth.internal-mesh.local",
      icon: "🔐",
      status: "online",
      glowColor: "rgba(16, 185, 129, 0.2)",
      borderColor: "rgba(16, 185, 129, 0.3)",
      shadowColor: "rgba(16, 185, 129, 0.15)",
      hoverColor: "#a7f3d0",
      iconBg: "rgba(16, 185, 129, 0.1)"
    },
    {
      title: "LiteLLM API Gateway",
      description: "Direct entry point for developer integrations. Access OpenAI-compatible routes natively.",
      url: "https://api.internal-mesh.local",
      icon: "⚡",
      status: "online",
      glowColor: "rgba(59, 130, 246, 0.2)",
      borderColor: "rgba(59, 130, 246, 0.3)",
      shadowColor: "rgba(59, 130, 246, 0.15)",
      hoverColor: "#bfdbfe",
      iconBg: "rgba(59, 130, 246, 0.1)"
    }
  ]

  return (
    <div className="portal-container">
      <header className="portal-header">
        <div className="portal-title-wrapper">
          <span className="portal-logo-glow">🌌</span>
          <h1 className="portal-title">Sovereign Enclave</h1>
        </div>
        <p className="portal-subtitle">
          Your fully private, offline dual-node AI inference cluster. Securely accessed via your LAN network.
        </p>
      </header>

      <div className="vpn-banner">
        <span className="vpn-dot"></span>
        <span>Secure Wireguard Gateway Connection Active</span>
      </div>

      <main className="services-grid">
        {services.map((svc) => (
          <a
            key={svc.title}
            href={svc.url}
            target="_blank"
            rel="noopener noreferrer"
            className="service-card"
            style={{
              '--card-glow': svc.glowColor,
              '--card-border': svc.borderColor,
              '--card-shadow': svc.shadowColor,
              '--card-hover-color': svc.hoverColor,
              '--card-icon-bg': svc.iconBg,
            } as React.CSSProperties}
          >
            <div>
              <div className="card-header">
                <span className="card-icon">{svc.icon}</span>
                <span className={`card-status ${svc.status}`}>{svc.status}</span>
              </div>
              <div className="card-body">
                <h2 className="card-title">{svc.title}</h2>
                <p className="card-description">{svc.description}</p>
              </div>
            </div>
            <div className="card-footer">
              <span>Launch Service</span>
              <span className="arrow-icon">→</span>
            </div>
          </a>
        ))}
      </main>

      <section className="system-console">
        <div className="console-header">
          <div className="console-dots">
            <span className="console-dot"></span>
            <span className="console-dot"></span>
            <span className="console-dot"></span>
          </div>
          <span className="console-title">enclave-sys-monitor</span>
        </div>
        <div className="console-body">
          <div className="console-column">
            <div className="console-row">
              <span className="label">Primary Mesh Domain:</span>
              <span className="value highlight">internal-mesh.local</span>
            </div>
            <div className="console-row">
              <span className="label">Cluster Orchestrator:</span>
              <span className="value">K3s v1.28+ / Zarf Offline</span>
            </div>
            <div className="console-row">
              <span className="label">Control Plane:</span>
              <span className="value">Beelink GTR9 Pro (Fedora 44)</span>
            </div>
          </div>
          <div className="console-column">
            <div className="console-row">
              <span className="label">GPU Worker:</span>
              <span className="value">RTX 4090 Workstation</span>
            </div>
            <div className="console-row">
              <span className="label">Analytical Model:</span>
              <span className="value highlight">DeepSeek-R1 70B GGUF</span>
            </div>
            <div className="console-row">
              <span className="label">Conversational Model:</span>
              <span className="value highlight">DeepSeek-R1 14B AWQ</span>
            </div>
          </div>
          <div className="console-column">
            <div className="console-row">
              <span className="label">Secret Management:</span>
              <span className="value green">OpenBao Hardened Shield</span>
            </div>
            <div className="console-row">
              <span className="label">Network Security:</span>
              <span className="value green">Microsegmented Policies</span>
            </div>
            <div className="console-row">
              <span className="label">Routing Mode:</span>
              <span className="value highlight">Client-Agnostic Gateway</span>
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}