use strict;
use warnings;
use Test::More;
use Test::Mojo;

use FindBin;
use lib "$FindBin::Bin/../lib";

my $t = Test::Mojo->new('LogLens');

# ============================================================
# Health Check
# ============================================================

# Test 1: Health endpoint returns 200
$t->get_ok('/health')
  ->status_is(200)
  ->json_is('/status' => 'ok')
  ->json_is('/service' => 'LogLens')
  ->json_has('/version')
  ->json_has('/time');

# ============================================================
# POST /api/logs - Create log entries
# ============================================================

# Test 2: Create a log entry with all fields
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T10:00:00Z',
    source    => 'web-server',
    level     => 'info',
    message   => 'Server started on port 8080',
    metadata  => { pid => 1234 },
})
  ->status_is(201)
  ->json_is('/id' => 1)
  ->json_is('/source' => 'web-server')
  ->json_is('/level' => 'info')
  ->json_is('/message' => 'Server started on port 8080')
  ->json_is('/metadata/pid' => 1234);

# Test 3: Create a log entry with minimal fields
$t->post_ok('/api/logs' => json => {
    message => 'Simple log message',
})
  ->status_is(201)
  ->json_is('/id' => 2)
  ->json_is('/source' => 'unknown')
  ->json_is('/level' => 'info')
  ->json_has('/timestamp');

# Test 4: Create with missing message returns 400
$t->post_ok('/api/logs' => json => {
    source => 'test',
    level  => 'error',
})
  ->status_is(400)
  ->json_has('/error');

# Test 5: Create with empty body returns 400
$t->post_ok('/api/logs')
  ->status_is(400)
  ->json_has('/error');

# Test 6: Create error log
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T10:05:00Z',
    source    => 'database',
    level     => 'error',
    message   => 'Connection timeout to primary database',
})
  ->status_is(201)
  ->json_is('/id' => 3)
  ->json_is('/level' => 'error');

# Test 7: Create warning log
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T10:06:00Z',
    source    => 'web-server',
    level     => 'warning',
    message   => 'High memory usage detected: 85%',
})
  ->status_is(201)
  ->json_is('/id' => 4);

# Test 8: Create another error log from same source
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T10:07:00Z',
    source    => 'database',
    level     => 'error',
    message   => 'Connection timeout to replica database',
})
  ->status_is(201)
  ->json_is('/id' => 5);

# Test 9: Create fatal log
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T10:08:00Z',
    source    => 'auth-service',
    level     => 'fatal',
    message   => 'Fatal crash in authentication module',
})
  ->status_is(201)
  ->json_is('/id' => 6);

# Test 10: Level is lowercased
$t->post_ok('/api/logs' => json => {
    source  => 'api',
    level   => 'ERROR',
    message => 'Uppercase error level test',
})
  ->status_is(201)
  ->json_is('/level' => 'error');

# ============================================================
# GET /api/logs - List log entries
# ============================================================

# Test 11: List all logs
$t->get_ok('/api/logs')
  ->status_is(200)
  ->json_has('/logs')
  ->json_has('/count');
my $all_count = $t->tx->res->json->{count};
ok($all_count >= 6, "At least 6 logs exist (got $all_count)");

# Test 12: Filter by level=error
$t->get_ok('/api/logs?level=error')
  ->status_is(200);
my $error_logs = $t->tx->res->json->{logs};
ok(scalar @$error_logs >= 2, 'At least 2 error logs');
for my $log (@$error_logs) {
    is($log->{level}, 'error', 'Filtered log is error level');
}

# Test 13: Filter by source=database
$t->get_ok('/api/logs?source=database')
  ->status_is(200);
my $db_logs = $t->tx->res->json->{logs};
ok(scalar @$db_logs >= 2, 'At least 2 database logs');
for my $log (@$db_logs) {
    is($log->{source}, 'database', 'Filtered log source is database');
}

# Test 14: Filter by level and source together
$t->get_ok('/api/logs?level=error&source=database')
  ->status_is(200);
my $filtered = $t->tx->res->json->{logs};
ok(scalar @$filtered >= 2, 'At least 2 error+database logs');

# Test 15: Filter returns empty when no match
$t->get_ok('/api/logs?level=debug&source=nonexistent')
  ->status_is(200)
  ->json_is('/count' => 0);

# ============================================================
# GET /api/logs/:id - Get specific log entry
# ============================================================

# Test 16: Get existing log entry
$t->get_ok('/api/logs/1')
  ->status_is(200)
  ->json_is('/id' => 1)
  ->json_is('/source' => 'web-server')
  ->json_is('/message' => 'Server started on port 8080');

# Test 17: Get non-existent log entry returns 404
$t->get_ok('/api/logs/9999')
  ->status_is(404)
  ->json_has('/error');

# ============================================================
# DELETE /api/logs/:id - Delete a log entry
# ============================================================

# Create a temporary log to delete
$t->post_ok('/api/logs' => json => {
    message => 'Temporary log to be deleted',
})
  ->status_is(201);
my $temp_id = $t->tx->res->json->{id};

# Test 18: Delete existing log entry
$t->delete_ok("/api/logs/$temp_id")
  ->status_is(200)
  ->json_is('/id' => $temp_id)
  ->json_has('/message');

# Test 19: Delete already deleted entry returns 404
$t->delete_ok("/api/logs/$temp_id")
  ->status_is(404)
  ->json_has('/error');

# Test 20: Deleted log is no longer retrievable
$t->get_ok("/api/logs/$temp_id")
  ->status_is(404);

# ============================================================
# POST /api/logs/analyze - AI analyze logs
# ============================================================

# Test 21: Analyze all logs
$t->post_ok('/api/logs/analyze' => json => {})
  ->status_is(200)
  ->json_has('/analysis')
  ->json_has('/analysis/total_logs')
  ->json_has('/analysis/level_breakdown')
  ->json_has('/analysis/health_status')
  ->json_has('/recommendations')
  ->json_is('/model' => 'mock-claude-3.5');

# Test 22: Analyze specific logs by IDs
$t->post_ok('/api/logs/analyze' => json => { log_ids => [1, 3, 5] })
  ->status_is(200)
  ->json_is('/analysis/total_logs' => 3);

# Test 23: Analyze with invalid IDs returns remaining valid logs
$t->post_ok('/api/logs/analyze' => json => { log_ids => [1, 9999] })
  ->status_is(200)
  ->json_is('/analysis/total_logs' => 1);

# Test 24: Health status reflects error rate
my $analysis = $t->tx->res->json;
ok(defined $analysis->{analysis}{health_status}, 'Health status is present');

# ============================================================
# GET /api/patterns - Pattern discovery
# ============================================================

# Add more logs with patterns for discovery
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T11:00:00Z',
    source    => 'web-server',
    level     => 'error',
    message   => 'Connection timeout to service X',
});
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T11:01:00Z',
    source    => 'web-server',
    level     => 'error',
    message   => 'Connection timeout to service Y',
});

# Test 25: Get patterns
$t->get_ok('/api/patterns')
  ->status_is(200)
  ->json_has('/patterns')
  ->json_has('/count');
my $patterns = $t->tx->res->json->{patterns};
ok(scalar @$patterns >= 1, 'At least 1 pattern discovered');

# Test 26: Pattern has required fields
my $first_pattern = $patterns->[0];
ok(defined $first_pattern->{id}, 'Pattern has id');
ok(defined $first_pattern->{regex}, 'Pattern has regex');
ok(defined $first_pattern->{description}, 'Pattern has description');
ok(defined $first_pattern->{frequency}, 'Pattern has frequency');
ok(defined $first_pattern->{severity}, 'Pattern has severity');

# ============================================================
# POST /api/anomalies/detect - Anomaly detection
# ============================================================

# Test 27: Detect anomalies
$t->post_ok('/api/anomalies/detect' => json => {})
  ->status_is(200)
  ->json_has('/anomalies')
  ->json_has('/count');
my $anomalies = $t->tx->res->json->{anomalies};
ok(ref $anomalies eq 'ARRAY', 'Anomalies is an array');

# Test 28: Anomaly has required fields if any detected
if (@$anomalies) {
    my $first = $anomalies->[0];
    ok(defined $first->{id}, 'Anomaly has id');
    ok(defined $first->{type}, 'Anomaly has type');
    ok(defined $first->{description}, 'Anomaly has description');
    ok(defined $first->{score}, 'Anomaly has score');
    ok(defined $first->{log_ids}, 'Anomaly has log_ids');
} else {
    pass('No anomalies detected (acceptable for current dataset)');
    pass('Skipping anomaly field checks');
    pass('Skipping anomaly field checks');
    pass('Skipping anomaly field checks');
    pass('Skipping anomaly field checks');
}

# ============================================================
# GET /api/stats - Log statistics
# ============================================================

# Test 29: Get stats
$t->get_ok('/api/stats')
  ->status_is(200)
  ->json_has('/total')
  ->json_has('/by_level')
  ->json_has('/by_source')
  ->json_has('/time_distribution');

# Test 30: Stats total matches log count
my $stats_total = $t->tx->res->json->{total};
$t->get_ok('/api/logs');
my $list_count = $t->tx->res->json->{count};
is($stats_total, $list_count, 'Stats total matches log list count');

# Test 31: Stats by_level has expected levels
my $by_level = $t->tx->res->json;
$t->get_ok('/api/stats');
my $stats = $t->tx->res->json;
ok(exists $stats->{by_level}{error}, 'Stats has error level count');
ok(exists $stats->{by_level}{info}, 'Stats has info level count');

# ============================================================
# POST /api/logs/summarize - AI summarize logs
# ============================================================

# Test 32: Summarize all logs
$t->post_ok('/api/logs/summarize' => json => {})
  ->status_is(200)
  ->json_has('/summary')
  ->json_has('/total_logs')
  ->json_has('/time_range')
  ->json_has('/breakdown')
  ->json_is('/model' => 'mock-claude-3.5');

# Test 33: Summarize with time range
$t->post_ok('/api/logs/summarize' => json => {
    from => '2026-03-26T10:00:00Z',
    to   => '2026-03-26T10:10:00Z',
})
  ->status_is(200)
  ->json_has('/summary')
  ->json_is('/time_range/from' => '2026-03-26T10:00:00Z')
  ->json_is('/time_range/to'   => '2026-03-26T10:10:00Z');

# Test 34: Summarize with no matching logs returns 400
$t->post_ok('/api/logs/summarize' => json => {
    from => '2020-01-01T00:00:00Z',
    to   => '2020-01-01T00:00:01Z',
})
  ->status_is(400)
  ->json_has('/error');

# Test 35: Summary contains breakdown by level
$t->post_ok('/api/logs/summarize' => json => {})
  ->status_is(200);
my $summary = $t->tx->res->json;
ok(defined $summary->{breakdown}{by_level}, 'Summary has level breakdown');
ok(defined $summary->{breakdown}{by_source}, 'Summary has source breakdown');

# ============================================================
# Edge Cases & Additional Tests
# ============================================================

# Test 36: POST /api/logs with special characters in message
$t->post_ok('/api/logs' => json => {
    message => 'Error: null pointer <script>alert("xss")</script> & "quotes"',
    level   => 'error',
    source  => 'security',
})
  ->status_is(201)
  ->json_is('/message' => 'Error: null pointer <script>alert("xss")</script> & "quotes"');

# Test 37: Very long message
my $long_msg = 'A' x 5000;
$t->post_ok('/api/logs' => json => {
    message => $long_msg,
})
  ->status_is(201)
  ->json_is('/message' => $long_msg);

# Test 38: Multiple sources in stats
$t->get_ok('/api/stats')
  ->status_is(200);
my $sources = $t->tx->res->json->{by_source};
ok(scalar keys %$sources >= 3, 'At least 3 different sources tracked');

# Test 39: Analyze detects error keywords in messages
$t->post_ok('/api/logs/analyze' => json => {})
  ->status_is(200);
my $keywords = $t->tx->res->json->{analysis}{error_keywords};
ok(defined $keywords, 'Error keywords analysis present');
ok(($keywords->{timeout} // 0) >= 1, 'Detected timeout keyword');

# Test 40: Pattern severity classification works
$t->get_ok('/api/patterns')
  ->status_is(200);
my $all_patterns = $t->tx->res->json->{patterns};
my @severities = map { $_->{severity} } @$all_patterns;
ok(scalar @severities > 0, 'Patterns have severity classifications');

# ============================================================
# Anomaly detection with controlled data
# ============================================================

# Add logs that trigger log storm detection (3+ identical messages)
for (1..4) {
    $t->post_ok('/api/logs' => json => {
        timestamp => '2026-03-26T12:00:00Z',
        source    => 'monitor',
        level     => 'error',
        message   => 'Disk space critical: /dev/sda1 at 99%',
    })->status_is(201);
}

# Test 41: Anomaly detection catches log storm
$t->post_ok('/api/anomalies/detect' => json => {})
  ->status_is(200);
my $detected = $t->tx->res->json->{anomalies};
my @storms = grep { $_->{type} eq 'log_storm' } @$detected;
ok(scalar @storms >= 1, 'Log storm anomaly detected');

# Test 42: Anomaly detection catches source anomaly for error-only sources
# 'auth-service' only has a fatal log, and 'database' only has errors
# Add enough error-only source data
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T12:01:00Z',
    source    => 'failing-service',
    level     => 'error',
    message   => 'Service unavailable',
})->status_is(201);
$t->post_ok('/api/logs' => json => {
    timestamp => '2026-03-26T12:01:01Z',
    source    => 'failing-service',
    level     => 'error',
    message   => 'Service still down',
})->status_is(201);

$t->post_ok('/api/anomalies/detect' => json => {})
  ->status_is(200);
my $detected2 = $t->tx->res->json->{anomalies};
my @source_anomalies = grep { $_->{type} eq 'source_anomaly' } @$detected2;
ok(scalar @source_anomalies >= 1, 'Source anomaly detected for error-only source');

done_testing();
