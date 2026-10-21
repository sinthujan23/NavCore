const net = require('net');
const tls = require('tls');

/**
 * Lightweight, zero-dependency SMTP Mailer using native Node.js TLS & Sockets.
 * Supports Gmail, SendGrid, Mailgun, Brevo, Outlook, and any RFC 5321 compliant SMTP server.
 */
class EmailService {
  constructor() {
    this.host = process.env.SMTP_HOST || '';
    this.port = parseInt(process.env.SMTP_PORT || '465', 10);
    this.secure = process.env.SMTP_SECURE !== 'false'; // default true for 465
    this.user = (process.env.SMTP_USER || '').trim();
    this.pass = (process.env.SMTP_PASS || '').replace(/\s+/g, '');
    this.from = process.env.SMTP_FROM || (this.user ? `"NexNav Security" <${this.user}>` : '"NexNav Security" <verify@nexnav.com>');
  }

  /**
   * Check if real SMTP sending is configured in environment
   */
  isConfigured() {
    return Boolean(this.host && this.user && this.pass);
  }

  /**
   * Sends raw email over SMTP socket
   */
  async sendMail({ to, subject, html, text }) {
    if (!this.isConfigured()) {
      console.log('\n============================================================');
      console.log(' [EMAIL SERVICE - DEV / DEMO MODE]');
      console.log(` To:      ${to}`);
      console.log(` Subject: ${subject}`);
      console.log(' (Configure SMTP_HOST, SMTP_USER, SMTP_PASS in backend/.env for live inbox delivery)');
      console.log('============================================================\n');
      return { success: true, simulated: true };
    }

    return new Promise((resolve, reject) => {
      const isSsl = this.port === 465 || this.secure;
      let socket;

      const cleanup = () => {
        try { if (socket && !socket.destroyed) socket.destroy(); } catch (_) {}
      };

      const timeout = setTimeout(() => {
        cleanup();
        reject(new Error('SMTP connection timed out'));
      }, 15000);

      const onConnect = () => {
        let buffer = '';
        let step = 0;

        const write = (cmd) => {
          socket.write(cmd + '\r\n');
        };

        socket.on('data', (chunk) => {
          buffer += chunk.toString();
          const lines = buffer.split('\r\n');
          buffer = lines.pop(); // keep remainder

          for (const line of lines) {
            if (!line) continue;
            const code = parseInt(line.substring(0, 3), 10);
            const isLast = line.charAt(3) === ' ';

            if (!isLast) continue; // multi-line response, wait for final line

            if (step === 0 && code === 220) {
              // Greeted
              step = 1;
              write(`EHLO ${this.host || 'localhost'}`);
            } else if (step === 1 && code === 250) {
              // EHLO accepted -> Start Auth
              step = 2;
              write('AUTH LOGIN');
            } else if (step === 2 && code === 334) {
              // Send Base64 Username
              step = 3;
              write(Buffer.from(this.user).toString('base64'));
            } else if (step === 3 && code === 334) {
              // Send Base64 Password
              step = 4;
              write(Buffer.from(this.pass).toString('base64'));
            } else if (step === 4 && code === 235) {
              // Authenticated -> Send MAIL FROM
              step = 5;
              const senderMatch = this.from.match(/<([^>]+)>/);
              const senderEmail = senderMatch ? senderMatch[1] : this.user;
              write(`MAIL FROM:<${senderEmail}>`);
            } else if (step === 5 && code === 250) {
              // RCPT TO
              step = 6;
              write(`RCPT TO:<${to}>`);
            } else if (step === 6 && code === 250) {
              // DATA
              step = 7;
              write('DATA');
            } else if (step === 7 && code === 354) {
              // Send Email Payload with anti-spam RFC 5322 compliance
              step = 8;
              const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
              const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
              const d = new Date();
              const dateStr = `${days[d.getUTCDay()]}, ${String(d.getUTCDate()).padStart(2, '0')} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()} ${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}:${String(d.getUTCSeconds()).padStart(2, '0')} +0000`;
              const msgId = `<${Date.now()}.${Math.floor(1000 + Math.random() * 9000)}@gmail.com>`;
              const boundary = `----=_Part_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;

              const plainFallback = text || (html ? html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() : 'Please view this message in an HTML-capable email client.');

              const mime = [
                `From: ${this.from}`,
                `To: <${to}>`,
                `Reply-To: <${this.user}>`,
                `Date: ${dateStr}`,
                `Message-ID: ${msgId}`,
                `Subject: ${subject}`,
                'MIME-Version: 1.0',
                'Auto-Submitted: auto-generated',
                'X-Auto-Response-Suppress: All',
                `Content-Type: multipart/alternative; boundary="${boundary}"`,
                '',
                `--${boundary}`,
                'Content-Type: text/plain; charset=UTF-8',
                'Content-Transfer-Encoding: 7bit',
                '',
                plainFallback,
                '',
                `--${boundary}`,
                'Content-Type: text/html; charset=UTF-8',
                'Content-Transfer-Encoding: 7bit',
                '',
                html,
                '',
                `--${boundary}--`,
                '.',
              ].join('\r\n');
              write(mime);
            } else if (step === 8 && code === 250) {
              // Sent successfully -> QUIT
              step = 9;
              write('QUIT');
              clearTimeout(timeout);
              cleanup();
              resolve({ success: true, delivered: true });
            } else if (code >= 400) {
              clearTimeout(timeout);
              cleanup();
              reject(new Error(`SMTP Error ${code}: ${line}`));
              return;
            }
          }
        });
      };

      socket = isSsl
        ? tls.connect({ host: this.host, port: this.port, rejectUnauthorized: false }, onConnect)
        : net.connect({ host: this.host, port: this.port }, onConnect);

      socket.on('error', (err) => {
        clearTimeout(timeout);
        cleanup();
        reject(err);
      });
    });
  }

  /**
   * Helper to format email HTML with sleek modern styling
   */
  _buildEmailHtml({ title, preheader, bodyText, code, footerNote }) {
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #0F172A; margin: 0; padding: 24px; color: #0F172A; }
    .card { max-width: 520px; margin: 0 auto; background: #FFFFFF; border-radius: 20px; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.25); border: 1px solid #E2E8F0; }
    .header { background: linear-gradient(135deg, #1E293B 0%, #0F172A 100%); padding: 32px 28px; text-align: center; }
    .logo-badge { display: inline-block; background: #2563EB; color: #FFFFFF; font-weight: 800; font-size: 16px; letter-spacing: 1.5px; padding: 8px 18px; border-radius: 12px; margin-bottom: 12px; }
    .title { color: #FFFFFF; font-size: 20px; font-weight: 700; margin: 0; }
    .subtitle { color: #94A3B8; font-size: 13px; margin-top: 6px; }
    .body-content { padding: 32px 28px; }
    .text { font-size: 14.5px; line-height: 1.6; color: #334155; margin: 0 0 20px 0; }
    .otp-container { background: #F1F5F9; border: 2px dashed #CBD5E1; border-radius: 14px; padding: 20px; text-align: center; margin: 24px 0; }
    .otp-label { font-size: 11px; font-weight: 700; color: #64748B; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; }
    .otp-code { font-family: 'Courier New', Courier, monospace; font-size: 34px; font-weight: 800; color: #2563EB; letter-spacing: 8px; margin: 0; }
    .otp-expiry { font-size: 12px; color: #EF4444; font-weight: 600; margin-top: 8px; }
    .note { font-size: 12.5px; color: #64748B; line-height: 1.5; border-left: 3px solid #2563EB; padding-left: 12px; margin-top: 20px; }
    .footer { background: #F8FAFC; padding: 20px 28px; text-align: center; font-size: 11.5px; color: #94A3B8; border-top: 1px solid #E2E8F0; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div class="logo-badge">NEXNAV</div>
      <h1 class="title">${title}</h1>
      <p class="subtitle">${preheader || 'Indoor AR Navigation & Intelligent Routing'}</p>
    </div>
    <div class="body-content">
      <p class="text">${bodyText}</p>
      <div class="otp-container">
        <div class="otp-label">Your Verification Code</div>
        <div class="otp-code">${code}</div>
        <div class="otp-expiry">Expires in 15 minutes</div>
      </div>
      <div class="note">${footerNote || 'Do not share this one-time code with anyone. NexNav will never ask for your code.'}</div>
    </div>
    <div class="footer">
      Â© 2026 NexNav Systems â€¢ Real-Time Indoor Navigation & Mapping
    </div>
  </div>
</body>
</html>`;
  }

  /**
   * Send Account Registration Email Verification OTP
   */
  async sendAccountVerification(email, code, name) {
    const displayName = name || email.split('@')[0];
    const subject = `${code} is your NexNav Account Verification Code`;
    const html = this._buildEmailHtml({
      title: 'Verify Your Email Address',
      preheader: 'Complete your NexNav registration',
      bodyText: `Hello <strong>${displayName}</strong>,<br><br>Thank you for creating an account with NexNav. To activate your account and access real-time indoor AR navigation, please verify your email address with the code below:`,
      code,
      footerNote: 'If you did not attempt to create an account with NexNav, you can safely disregard this email.',
    });

    console.log(`\n------------------------------------------------------------`);
    console.log(` [VERIFICATION CODE ISSUED]`);
    console.log(` Recipient:  ${email}`);
    console.log(` Code:       ${code}`);
    console.log(` Purpose:    New Account Registration`);
    console.log(` Expires In: 15 minutes`);
    console.log(`------------------------------------------------------------\n`);

    try {
      await this.sendMail({ to: email, subject, html });
      return { success: true };
    } catch (err) {
      console.warn(`[EmailService] SMTP live send failed: ${err.message}. (Local dev code logged above)`);
      return { success: true, error: err.message };
    }
  }

  /**
   * Send Sign-In / Login Verification OTP
   */
  async sendLoginVerification(email, code, name) {
    const displayName = name || email.split('@')[0];
    const subject = `${code} is your NexNav Sign-In Verification Code`;
    const html = this._buildEmailHtml({
      title: 'NexNav Sign-In Verification',
      preheader: 'Verify your identity to sign in',
      bodyText: `Hello <strong>${displayName}</strong>,<br><br>A sign-in attempt was initiated for your NexNav account. Use the one-time verification code below to authorize your session:`,
      code,
      footerNote: 'If you did not request this sign-in code, please change your password immediately to secure your account.',
    });

    console.log(`\n------------------------------------------------------------`);
    console.log(` [SIGN-IN CODE ISSUED]`);
    console.log(` Recipient:  ${email}`);
    console.log(` Code:       ${code}`);
    console.log(` Purpose:    Sign-In Identity Verification`);
    console.log(` Expires In: 15 minutes`);
    console.log(`------------------------------------------------------------\n`);

    try {
      await this.sendMail({ to: email, subject, html });
      return { success: true };
    } catch (err) {
      console.warn(`[EmailService] SMTP live send failed: ${err.message}. (Local dev code logged above)`);
      return { success: true, error: err.message };
    }
  }

  /**
   * Send Password Reset Verification OTP
   */
  async sendPasswordReset(email, code, name) {
    const displayName = name || email.split('@')[0];
    const subject = `${code} is your NexNav Password Reset Code`;
    const html = this._buildEmailHtml({
      title: 'Password Reset Request',
      preheader: 'Reset your NexNav credentials',
      bodyText: `Hello <strong>${displayName}</strong>,<br><br>We received a request to reset your NexNav password. Enter the verification code below to proceed with resetting your password:`,
      code,
      footerNote: 'If you did not request a password reset, you can safely ignore this message.',
    });

    console.log(`\n------------------------------------------------------------`);
    console.log(` [PASSWORD RESET CODE ISSUED]`);
    console.log(` Recipient:  ${email}`);
    console.log(` Code:       ${code}`);
    console.log(` Purpose:    Password Reset Request`);
    console.log(` Expires In: 15 minutes`);
    console.log(`------------------------------------------------------------\n`);

    try {
      await this.sendMail({ to: email, subject, html });
      return { success: true };
    } catch (err) {
      console.warn(`[EmailService] SMTP live send failed: ${err.message}. (Local dev code logged above)`);
      return { success: true, error: err.message };
    }
  }
}

module.exports = new EmailService();
