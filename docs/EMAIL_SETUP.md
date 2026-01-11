# Email Configuration Guide

This guide explains how to configure email (SMTP) for Authentik and Nextcloud, including:
- Sending password reset emails from Authentik
- Sending notifications from Nextcloud
- Creating client-specific email addresses @vrije.cloud

## Overview

The infrastructure supports automatic SMTP configuration for both Authentik and Nextcloud. Once configured, clients can:

1. **Authentik**: Send password reset emails, account notifications
2. **Nextcloud**: Send file sharing notifications, activity emails, calendar reminders

## Quick Start

### 1. Choose an Email Provider

| Provider | Best For | Pricing |
|----------|----------|---------|
| [Mailgun](https://www.mailgun.com/) | Transactional email, good deliverability | Free tier: 5,000 emails/month |
| [SendGrid](https://sendgrid.com/) | High volume, marketing + transactional | Free tier: 100 emails/day |
| [Postmark](https://postmarkapp.com/) | Best deliverability, transactional only | $15/month for 10,000 emails |
| Self-hosted (Mailcow) | Full control, privacy-focused | Server costs only |

### 2. Configure Shared Secrets

Edit the shared secrets file:

```bash
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/shared.sops.yaml
```

Add SMTP configuration:

```yaml
# Email/SMTP Configuration
smtp_enabled: true
smtp_host: "smtp.mailgun.org"          # Your SMTP server
smtp_port: "587"                        # Usually 587 for TLS, 465 for SSL
smtp_username: "postmaster@vrije.cloud" # SMTP username
smtp_password: "your-smtp-password"     # SMTP password
smtp_use_tls: true                      # Use STARTTLS (port 587)
smtp_use_ssl: false                     # Use implicit SSL (port 465)
email_provider: "mailgun"               # For documentation purposes
```

### 3. Configure Client Email Address

Each client can have their own email address for sending. Edit the client secrets:

```bash
SOPS_AGE_KEY_FILE=keys/age-key.txt sops secrets/clients/<client_name>.sops.yaml
```

Add/update:

```yaml
# Client-specific email address (used as "from" address)
client_email_address: "clientname@vrije.cloud"

# Admin email address (for Authentik admin user)
authentik_bootstrap_email: "admin@clientname.vrije.cloud"

# Nextcloud mail prefix (becomes nextcloud@clientdomain)
nextcloud_mail_from: "nextcloud"
```

### 4. Deploy/Redeploy

```bash
./scripts/deploy-client.sh <client_name>
```

## Provider-Specific Setup

### Mailgun

1. **Sign up** at [mailgun.com](https://www.mailgun.com/)

2. **Add your domain**: `vrije.cloud`

3. **Configure DNS** (Mailgun provides exact records):
   ```
   TXT  @              "v=spf1 include:mailgun.org ~all"
   TXT  smtp._domainkey  k=rsa; p=MIGf...
   TXT  _dmarc         "v=DMARC1; p=quarantine"
   ```

4. **Create SMTP credentials** in Mailgun dashboard

5. **Update shared secrets**:
   ```yaml
   smtp_enabled: true
   smtp_host: "smtp.mailgun.org"
   smtp_port: "587"
   smtp_username: "postmaster@vrije.cloud"
   smtp_password: "<smtp-password-from-mailgun>"
   smtp_use_tls: true
   ```

### SendGrid

1. **Sign up** at [sendgrid.com](https://sendgrid.com/)

2. **Create API key** with "Mail Send" permission

3. **Set up sender authentication** for `vrije.cloud`

4. **Update shared secrets**:
   ```yaml
   smtp_enabled: true
   smtp_host: "smtp.sendgrid.net"
   smtp_port: "587"
   smtp_username: "apikey"
   smtp_password: "<your-sendgrid-api-key>"
   smtp_use_tls: true
   ```

### Postmark

1. **Sign up** at [postmarkapp.com](https://postmarkapp.com/)

2. **Create a server** and get the API token

3. **Add sender signature** for `vrije.cloud`

4. **Update shared secrets**:
   ```yaml
   smtp_enabled: true
   smtp_host: "smtp.postmarkapp.com"
   smtp_port: "587"
   smtp_username: "<server-api-token>"
   smtp_password: "<server-api-token>"
   smtp_use_tls: true
   ```

### Self-Hosted (Mailcow)

For full control over email, deploy Mailcow:

1. **Deploy Mailcow** on a separate server:
   ```bash
   git clone https://github.com/mailcow/mailcow-dockerized
   cd mailcow-dockerized
   ./generate_config.sh
   docker compose up -d
   ```

2. **Configure DNS**:
   ```
   MX   @     10   mail.vrije.cloud
   A    mail       <server-ip>
   TXT  @          "v=spf1 a mx ~all"
   TXT  dkim._domainkey  <generated-by-mailcow>
   TXT  _dmarc     "v=DMARC1; p=quarantine"
   ```

3. **Create mailbox** for each client: `clientname@vrije.cloud`

4. **Update shared secrets**:
   ```yaml
   smtp_enabled: true
   smtp_host: "mail.vrije.cloud"
   smtp_port: "587"
   smtp_username: "noreply@vrije.cloud"
   smtp_password: "<mailbox-password>"
   smtp_use_tls: true
   ```

## DNS Configuration

Regardless of provider, ensure proper email authentication records:

### SPF Record
Specifies which servers can send email for your domain.

```
TXT  @  "v=spf1 include:<provider-include> ~all"
```

### DKIM Record
Cryptographic signature for email authentication.

```
TXT  <selector>._domainkey  "k=rsa; p=<public-key>"
```

### DMARC Record
Policy for handling authentication failures.

```
TXT  _dmarc  "v=DMARC1; p=quarantine; rua=mailto:dmarc@vrije.cloud"
```

## Client Email Addresses

Each client server can have a unique sending email address:

| Client | Email Address | Used For |
|--------|--------------|----------|
| test | test@vrije.cloud | Authentik & Nextcloud notifications |
| acme | acme@vrije.cloud | Authentik & Nextcloud notifications |

### Creating Client Email Address

The email address is configured in the client secrets file:

```yaml
# In secrets/clients/<client>.sops.yaml
client_email_address: "client@vrije.cloud"
```

For **transactional providers** (Mailgun, SendGrid, Postmark):
- No mailbox creation needed
- Sender domain must be verified
- Emails appear as `from: client@vrije.cloud`

For **self-hosted email**:
- Create actual mailbox in Mailcow
- Or use catchall address for the domain

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Email Flow                            │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────┐     SMTP      ┌──────────────────┐    │
│  │  Authentik  │ ──────────────▶│  Email Provider  │    │
│  │   Server    │               │  (Mailgun, etc)  │    │
│  └─────────────┘               └────────┬─────────┘    │
│                                          │              │
│  ┌─────────────┐     SMTP               │              │
│  │  Nextcloud  │ ──────────────▶────────┘              │
│  │   Server    │                         │              │
│  └─────────────┘                         ▼              │
│                                  ┌─────────────┐        │
│                                  │   User's    │        │
│                                  │   Inbox     │        │
│                                  └─────────────┘        │
└─────────────────────────────────────────────────────────┘
```

## Testing Email

After deployment, test email functionality:

### Test Authentik Email

1. Go to https://auth.client.vrije.cloud
2. Click "Forgot password"
3. Enter a valid email address
4. Check for password reset email

### Test Nextcloud Email

1. Go to https://nextcloud.client.vrije.cloud
2. Login as admin
3. Go to Settings → Personal Info
4. Verify email address is set
5. Share a file and enable email notification
6. Check for sharing email

### Check Logs

If emails aren't sending, check container logs:

```bash
# Authentik logs
ssh root@<server>
docker logs authentik-worker 2>&1 | grep -i email

# Nextcloud logs
docker exec nextcloud cat /var/www/html/data/nextcloud.log | grep -i mail
```

## Troubleshooting

### Emails Not Sending

1. **Check SMTP settings** in secrets/shared.sops.yaml
2. **Verify DNS records** are properly configured
3. **Check container logs** for SMTP errors
4. **Test SMTP connection** manually:
   ```bash
   openssl s_client -connect smtp.mailgun.org:587 -starttls smtp
   ```

### Emails Going to Spam

1. **Ensure SPF, DKIM, DMARC** records are set
2. **Use consistent from address**
3. **Don't send too many emails** at once
4. **Check email reputation** at mail-tester.com

### Authentication Failures

1. **Verify username/password** in secrets
2. **Check if TLS/SSL setting** matches port
3. **Ensure IP isn't blocked** by provider

## Security Considerations

1. **SMTP Credentials**: Stored encrypted with SOPS
2. **TLS Required**: Always use TLS for SMTP connections
3. **SPF/DKIM/DMARC**: Prevents email spoofing
4. **Rate Limiting**: Most providers have sending limits

## Next Steps

After configuring email:

1. **Create users in Authentik** - They'll receive welcome/password emails
2. **Test password reset flow** - Verify emails are delivered
3. **Configure Nextcloud notifications** - Users can receive sharing alerts
