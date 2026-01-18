# Uptime Kuma Email Notification Setup

## Quick Setup Guide

### 1. Access Uptime Kuma

Open: **https://status.vrije.cloud**

### 2. Navigate to Settings

1. Click on **Settings** (gear icon) in the left sidebar
2. Click on **Notifications**

### 3. Add Email (SMTP) Notification

1. Click **Setup Notification**
2. Select **Email (SMTP)**
3. Configure with these settings:

```
Notification Type: Email (SMTP)
Friendly Name: PTT Email Alerts

SMTP Settings:
  Hostname: smtp.strato.com
  Port: 587
  Security: STARTTLS (or "None" with TLS unchecked)

Authentication:
  Username: server@postxsociety.org
  Password: Mov!ePubl1cL0ndon@longW!7h

From Email: server@postxsociety.org
To Email: mail@postxsociety.org

Custom Subject (optional):
  [🔴 DOWN] {msg}
  [✅ UP] {msg}
```

### 4. Test the Notification

1. Click **Test** button
2. Check mail@postxsociety.org for test email
3. If successful, click **Save**

### 5. Apply to All Monitors

Option A - Apply when creating monitors:
- When creating each monitor, select this notification in the "Notifications" section

Option B - Apply to existing monitors:
1. Go to each monitor's settings (Edit button)
2. Scroll to "Notifications" section
3. Enable "PTT Email Alerts"
4. Click **Save**

### 6. Configure Alert Rules

In the notification settings or per-monitor:

**What to alert on:**
- ✅ **When service goes down** - Immediate alert
- ✅ **When service comes back up** - Immediate alert
- ✅ **Certificate expiring** - 30 days before
- ✅ **Certificate expiring** - 7 days before

**Alert frequency:**
- Send alert immediately when status changes
- Repeat notification every 60 minutes if still down (optional)

## Testing

After setup, test by:

1. Creating a test monitor pointing to a non-existent URL
2. Wait for it to show as "DOWN"
3. Verify email notification received
4. Delete the test monitor

## Troubleshooting

### No emails received

1. Check SMTP settings are correct
2. Test SMTP connection:
   ```bash
   telnet smtp.strato.com 587
   ```
3. Check spam/junk folder
4. Verify email address is correct

### Authentication failed

- Double-check username and password
- Ensure no extra spaces in credentials
- Try re-saving the notification

### Connection timeout

- Verify port 587 is not blocked by firewall
- Try port 25 or 465 (with SSL/TLS)
- Check if SMTP server allows connections from monitoring server IP

## Alternative: Use Environment Variables

If you want to configure email at container level, update the Docker Compose file:

```yaml
services:
  uptime-kuma:
    environment:
      # Add SMTP environment variables here if supported by future versions
```

Currently, Uptime Kuma requires web UI configuration for SMTP.

## Notification Settings Per Monitor

When creating monitors for clients, ensure:

- **HTTP(S) monitors**: Enable email notifications
- **SSL monitors**: Enable email notifications with 30-day and 7-day warnings
- **Alert threshold**: 3 failed checks before alerting (prevents false positives)

## Email Template

Uptime Kuma sends emails with:
- Monitor name
- Status (UP/DOWN)
- Timestamp
- Response time
- Error message (if applicable)
- Link to monitor in Uptime Kuma

## Best Practices

1. **Test regularly** - Verify emails are being received
2. **Multiple recipients** - Add additional email addresses for redundancy
3. **Alert fatigue** - Don't over-alert; use reasonable thresholds
4. **Maintenance mode** - Pause monitors during planned maintenance
5. **Group notifications** - Create notification groups for different teams

## Related

- [Monitoring Documentation](monitoring.md)
- Uptime Kuma Notification Docs: https://github.com/louislam/uptime-kuma/wiki/Notification-Methods
