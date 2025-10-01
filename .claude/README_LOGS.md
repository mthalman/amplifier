# Claude Code Hook Logs

Hook logs are stored in the data directory to make them accessible from the host machine.

## Log Location

**Default location**: `$AMPLIFIER_DATA_DIR/logs/`
- Local development: `.data/logs/`
- Docker container: `/app/amplifier-data/logs/`
- Host (when using Docker): `amplifier-data/logs/`

This allows you to access logs from your host machine when running in Docker.

## Log Files

Each hook creates its own timestamped log file:

- `stop_hook_YYYYMMDD.log` - Memory extraction hook logs
- `session_start_YYYYMMDD.log` - Session initialization and memory retrieval logs
- `post_tool_use_YYYYMMDD.log` - Claim validation hook logs

## Log Format

Logs follow this format:

```
[YYYY-MM-DD HH:MM:SS.mmm] [hook_name] [LEVEL] message
```

Log levels:

- `INFO` - General information about hook execution
- `DEBUG` - Detailed debugging information
- `WARN` - Warning conditions
- `ERROR` - Error conditions with stack traces

## Log Rotation

Logs are automatically cleaned up after 7 days to prevent disk usage issues.

## Viewing Logs

### From within Docker container:

```bash
tail -f $AMPLIFIER_DATA_DIR/logs/stop_hook_*.log
```

### From host machine (when using Docker):

```bash
# Tail logs in real-time
tail -f amplifier-data/logs/post_tool_use_$(date +%Y%m%d).log

# View all today's logs
cat amplifier-data/logs/*_$(date +%Y%m%d).log

# Search for errors across all logs
grep ERROR amplifier-data/logs/*.log

# List all log files
ls -la amplifier-data/logs/
```

### General commands:

To search for errors:

```bash
grep ERROR $AMPLIFIER_DATA_DIR/logs/*.log
```

To see today's logs:

```bash
ls -la $AMPLIFIER_DATA_DIR/logs/*_$(date +%Y%m%d).log
```

## Implementation

The logging is implemented in `.claude/tools/hook_logger.py` which provides:

- Automatic log directory creation
- Timestamped log files per hook
- Multiple log levels
- JSON preview capabilities
- Automatic cleanup of old logs
- Dual output to both file and stderr
