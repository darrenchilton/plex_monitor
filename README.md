# Plex Server Monitor

A robust monitoring solution for Plex Media Server on macOS that provides automated server monitoring, recovery, and event logging through Airtable. Features intelligent update detection, conservative reboot cycles, and comprehensive error handling.

## 🌟 Key Features

- **🔄 Continuous Monitoring** - Real-time Plex Media Server health checks every 5 minutes
- **🧠 Smart Update Detection** - Automatically pauses monitoring during Plex updates
- **🌐 Network Recovery** - Multi-stage network connectivity restoration (soft reset → DNS flush → hard reset)
- **⚡ Daily Speed Testing** - Tracks network performance at 2am EST with intelligent retry logic
- **🔒 Security Focused** - Minimal permissions, passwordless sudo only for required operations
- **🛡️ Hardware Protection** - Conservative reboot limits (maximum 1 per day)
- **📊 Comprehensive Logging** - Local log files + Airtable integration for notifications
- **✅ Success Notifications** - Know when issues are automatically resolved
- **🎬 Stream-Aware** - Never interrupts active Plex streams during speed tests

## 📋 Quick Start

### Prerequisites

- macOS (tested on macOS 12+)
- Plex Media Server installed and configured
- Administrative access
- Airtable account (for notifications)
- Python 3 with pip (for network speed testing)

### Installation

1. **Clone this repository**
```bash
   git clone git@github.com:darrenchilton/plex_monitor.git
   cd plex_monitor
```

2. **Copy monitoring script**
```bash
   sudo cp scripts/plex_monitor.sh /Users/plex/
   sudo chown plex:staff /Users/plex/plex_monitor.sh
   sudo chmod 755 /Users/plex/plex_monitor.sh
```

3. **Install LaunchDaemon**
```bash
   sudo cp config/com.user.plexmonitor.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.user.plexmonitor.plist
   sudo chmod 644 /Library/LaunchDaemons/com.user.plexmonitor.plist
```

4. **Configure environment variables**
```bash
   # Copy template
   sudo -u plex cp config/.plex_monitor_env.example /Users/plex/.plex_monitor_env
   
   # Edit with your actual tokens
   sudo -u plex nano /Users/plex/.plex_monitor_env
   
   # Secure the file
   sudo -u plex chmod 600 /Users/plex/.plex_monitor_env
```

5. **Set up passwordless sudo** (Required for network recovery)
```bash
   sudo visudo -f /etc/sudoers.d/plex-monitor
```
   
   Add these lines (press `i` to insert, `Esc` then `:wq` to save):
```
   plex ALL=(ALL) NOPASSWD: /usr/sbin/networksetup
   plex ALL=(ALL) NOPASSWD: /sbin/ifconfig
   plex ALL=(ALL) NOPASSWD: /usr/bin/dscacheutil
   plex ALL=(ALL) NOPASSWD: /usr/bin/killall
   plex ALL=(ALL) NOPASSWD: /sbin/shutdown
   plex ALL=(ALL) NOPASSWD: /bin/mkdir
   plex ALL=(ALL) NOPASSWD: /usr/sbin/chown
   plex ALL=(ALL) NOPASSWD: /bin/chmod
   plex ALL=(ALL) NOPASSWD: /usr/bin/touch
```

6. **Install speedtest-cli**
```bash
   python3 -m pip install speedtest-cli --user
   sudo ln -s /Users/plex/Library/Python/3.*/bin/speedtest-cli /usr/local/bin/speedtest-cli
   speedtest-cli --version  # Verify installation
```

7. **Start the monitor**
```bash
   sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.plist
```

## 🎯 Conservative Design Philosophy

This monitor prioritizes hardware longevity and system stability over aggressive recovery attempts.

### Reboot Strategy

| Feature | Setting | Purpose |
|---------|---------|---------|
| **Maximum Reboots** | 1 per day | Protects hardware from excessive cycling |
| **Reboot Delay** | 24 hours | Prevents rapid reboot loops |
| **Daily Reset** | Midnight | Fresh cycle each day |
| **Speed Tests** | 2am EST | Minimizes streaming impact |
| **Stream Detection** | Auto-delay | Never interrupts active viewing |

### Example: 4-Day Network Outage

- **Day 1**: 1 reboot → 24hr wait → 1 reboot → wait until next day
- **Day 2**: Reset → 1 reboot → 24hr wait → 1 reboot → wait
- **Day 3**: Reset → 1 reboot → 24hr wait → 1 reboot → wait
- **Day 4**: Reset → 1 reboot → 24hr wait → 1 reboot

**Result**: ~6-8 reboots over 4 days (vs. potentially hundreds with aggressive settings)

## 📊 Monitoring & Notifications

### What Gets Logged to Airtable

The monitor sends notifications for:

**Plex Server Events:**
- Plex restart attempts
- ✅ Plex restart successes
- Plex update detection

**Network Events:**
- Network restart attempts
- ✅ Network restoration (soft reset/DNS flush/hard reset)
- Network speed test results

**System Events:**
- System reboot notifications
- Reboot cycle status updates

**Note**: You receive BOTH alert notifications when issues are detected AND success notifications when they're resolved automatically.

### Local Log Files

- `/Users/plex/Library/Logs/plex_monitor.log` - Main activity log
- `/Users/plex/Library/Logs/network_speeds.log` - Speed test history
- `/Users/plex/Library/Logs/plex_monitor_error.log` - Error details
- `/Users/plex/Library/Logs/airtable_queue.json` - Offline event queue
- `/Users/plex/Library/Logs/reboot_history.json` - Reboot cycle tracking
- `/Users/plex/Library/Logs/speed_test_history.json` - Speed test attempts

## ⚙️ Configuration

### Main Settings (in `scripts/plex_monitor.sh`)
```bash
CHECK_INTERVAL=300               # Check frequency (5 minutes)
MAX_RETRIES=2                   # Max Plex restart attempts
NETWORK_RESTART_ATTEMPTS=3      # Max network restart attempts
MAX_REBOOT_ATTEMPTS=1          # Max reboots per cycle
REBOOT_CYCLE_PAUSE=86400       # 24 hours between cycles
SPEED_TEST_HOUR=2              # Run speed test at 2am
SPEED_TEST_TIMEZONE='America/New_York'  # EST
```

### Network Test Endpoints
```bash
NETWORK_TEST_ENDPOINTS=(
    "1.1.1.1"         # Cloudflare
    "8.8.8.8"         # Google
    "208.67.222.222"  # OpenDNS
    "9.9.9.9"         # Quad9
)
```

## 🔧 Basic Commands
```bash
# Check if monitor is running
sudo launchctl list | grep plexmonitor
ps aux | grep plex_monitor

# View recent activity
tail -20 /Users/plex/Library/Logs/plex_monitor.log

# Monitor in real-time
tail -f /Users/plex/Library/Logs/plex_monitor.log

# View speed test results
tail -10 /Users/plex/Library/Logs/network_speeds.log

# Stop monitoring
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.plist

# Start monitoring
sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.plist

# Restart monitoring
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.plist
sudo launchctl load /Library/LaunchDaemons/com.user.plexmonitor.plist
```

## 🔐 Security

- **Environment Files**: Secured with 600 permissions (user read/write only)
- **Passwordless Sudo**: Restricted to specific binaries only
- **No Hardcoded Secrets**: All tokens stored in separate environment file
- **API Rate Limiting**: All external calls are rate-limited
- **Minimal Permissions**: Script runs with least privilege required

## 🐛 Troubleshooting

### Script Not Starting
```bash
# Check if running
ps aux | grep plex_monitor

# Check LaunchDaemon status
sudo launchctl list | grep plexmonitor

# Verify permissions
ls -l /Users/plex/plex_monitor.sh
ls -l /Library/LaunchDaemons/com.user.plexmonitor.plist
```

### Permission Errors
```bash
# Verify sudoers file exists
sudo cat /etc/sudoers.d/plex-monitor

# Test sudo without password
sudo -u plex sudo -n /usr/sbin/networksetup -listallnetworkservices

# If it asks for password, sudoers file needs to be reconfigured
```

### Speed Test Issues
```bash
# Test speedtest-cli manually
speedtest-cli --simple

# Check speed test history
cat /Users/plex/Library/Logs/speed_test_history.json

# Verify installation
which speedtest-cli
speedtest-cli --version
```

### Network Recovery Issues
```bash
# Check network interface
ifconfig en0

# Test connectivity manually
ping -c 3 8.8.8.8

# View reboot history
cat /Users/plex/Library/Logs/reboot_history.json
```

### Emergency: Stop Excessive API Calls
```bash
# Stop monitor immediately
sudo launchctl unload /Library/LaunchDaemons/com.user.plexmonitor.plist

# Clear event queue
echo "[]" | sudo tee /Users/plex/Library/Logs/airtable_queue.json

# Reset reboot history
echo '{"last_reboot": null, "attempts": 0, "cycle": 1, "last_cycle_start": null}' | sudo tee /Users/plex/Library/Logs/reboot_history.json
```

## 📈 Performance Impact

The conservative settings minimize system impact:

- **Network checks**: Every 5 minutes
- **Plex restarts**: Only when Plex is actually down
- **System reboots**: Maximum 2 per day during extended outages
- **API calls**: Batched and queued to reduce load
- **Speed tests**: Once per day (or less if streams active)
- **Speed test duration**: 30-45 seconds per test
- **Speed test bandwidth**: ~100-200 MB per test

## 🛡️ Hardware Protection

This version is designed to protect your Mac hardware:

- **Minimal reboots**: 1 per day maximum during outages
- **24-hour delays**: Prevents rapid cycling
- **Update awareness**: Won't interfere with Plex updates
- **Conservative approach**: Prioritizes hardware longevity
- **Stream-aware**: Never impacts active streaming

## 🔄 Version History

- **v3.1** (2025-11) - Added success notifications for network recoveries
- **v3.0** (2025-11) - Added daily network speed testing with intelligent retry logic
- **v2.0** (2025) - Conservative reboot implementation (1/day max, 24hr delays)
- **v1.0** (2024) - Initial release

## 🤝 Contributing

Improvements are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on your system
5. Submit a pull request with detailed description

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

## 💡 Tips

- Set up Airtable → Slack integration for instant mobile notifications
- Review logs weekly to identify patterns
- Rotate API tokens quarterly for security
- Keep backups of your configuration files
- Test changes in isolation before deploying

## 📞 Support

For issues:
1. Check the error log: `tail -20 /Users/plex/Library/Logs/plex_monitor_error.log`
2. Verify permissions are correct
3. Ensure tokens are valid in `/Users/plex/.plex_monitor_env`
4. Test network connectivity manually
5. Review the troubleshooting section above

---

**Repository**: https://github.com/darrenchilton/plex_monitor  
**Status**: Production-ready, actively maintained  
**Last Updated**: November 2025
