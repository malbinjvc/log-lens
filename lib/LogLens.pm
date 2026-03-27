package LogLens;
use Mojo::Base 'Mojolicious', -signatures;

use LogLens::Models;
use LogLens::Services;
use LogLens::Clients;

sub startup ($self) {
    # Initialize in-memory storage
    my $store = LogLens::Models::Store->new;

    # Initialize services
    my $claude_client    = LogLens::Clients::MockClaudeClient->new;
    my $log_service      = LogLens::Services::LogService->new(store => $store);
    my $pattern_service  = LogLens::Services::PatternService->new(store => $store);
    my $anomaly_service  = LogLens::Services::AnomalyService->new(
        store         => $store,
        claude_client => $claude_client,
    );

    # Store helpers
    $self->helper(log_service     => sub { $log_service });
    $self->helper(pattern_service => sub { $pattern_service });
    $self->helper(anomaly_service => sub { $anomaly_service });
    $self->helper(claude_client   => sub { $claude_client });

    my $r = $self->routes;

    # Health check
    $r->get('/health' => sub ($c) {
        $c->render(json => {
            status  => 'ok',
            service => 'LogLens',
            version => '1.0.0',
            time    => _now(),
        });
    });

    # POST /api/logs - Ingest a new log entry
    $r->post('/api/logs' => sub ($c) {
        my $data = $c->req->json;
        unless ($data && $data->{message}) {
            return $c->render(json => { error => 'message is required' }, status => 400);
        }
        my $entry = $c->log_service->create($data);
        $c->render(json => $entry, status => 201);
    });

    # GET /api/logs - List all log entries with optional filters
    $r->get('/api/logs' => sub ($c) {
        my $level  = $c->param('level');
        my $source = $c->param('source');
        my $logs   = $c->log_service->list(level => $level, source => $source);
        $c->render(json => { logs => $logs, count => scalar @$logs });
    });

    # GET /api/logs/:id - Get a specific log entry
    $r->get('/api/logs/:id' => sub ($c) {
        my $id    = $c->param('id');
        my $entry = $c->log_service->get($id);
        unless ($entry) {
            return $c->render(json => { error => 'Log entry not found' }, status => 404);
        }
        $c->render(json => $entry);
    });

    # DELETE /api/logs/:id - Delete a log entry
    $r->delete('/api/logs/:id' => sub ($c) {
        my $id      = $c->param('id');
        my $deleted = $c->log_service->delete($id);
        unless ($deleted) {
            return $c->render(json => { error => 'Log entry not found' }, status => 404);
        }
        $c->render(json => { message => 'Log entry deleted', id => $id });
    });

    # POST /api/logs/analyze - AI-analyze a batch of logs
    $r->post('/api/logs/analyze' => sub ($c) {
        my $data = $c->req->json // {};
        my $log_ids = $data->{log_ids};
        my $logs;
        if ($log_ids && ref $log_ids eq 'ARRAY' && @$log_ids) {
            $logs = [ grep { defined } map { $c->log_service->get($_) } @$log_ids ];
        } else {
            $logs = $c->log_service->list();
        }
        unless (@$logs) {
            return $c->render(json => { error => 'No logs to analyze' }, status => 400);
        }
        my $analysis = $c->claude_client->analyze_logs($logs);
        $c->render(json => $analysis);
    });

    # GET /api/patterns - Get discovered patterns
    $r->get('/api/patterns' => sub ($c) {
        my $logs     = $c->log_service->list();
        my $patterns = $c->pattern_service->discover($logs);
        $c->render(json => { patterns => $patterns, count => scalar @$patterns });
    });

    # POST /api/anomalies/detect - Detect anomalies
    $r->post('/api/anomalies/detect' => sub ($c) {
        my $data = $c->req->json // {};
        my $logs = $c->log_service->list();
        unless (@$logs) {
            return $c->render(json => { error => 'No logs available for anomaly detection' }, status => 400);
        }
        my $anomalies = $c->anomaly_service->detect($logs, $data);
        $c->render(json => { anomalies => $anomalies, count => scalar @$anomalies });
    });

    # GET /api/stats - Get log statistics
    $r->get('/api/stats' => sub ($c) {
        my $stats = $c->log_service->stats();
        $c->render(json => $stats);
    });

    # POST /api/logs/summarize - AI-summarize logs
    $r->post('/api/logs/summarize' => sub ($c) {
        my $data = $c->req->json // {};
        my $from = $data->{from};
        my $to   = $data->{to};
        my $logs = $c->log_service->list();

        # Filter by time range if provided
        if ($from || $to) {
            $logs = [
                grep {
                    my $ts = $_->{timestamp} // '';
                    (!$from || $ts ge $from) && (!$to || $ts le $to);
                } @$logs
            ];
        }

        unless (@$logs) {
            return $c->render(json => { error => 'No logs found in the specified range' }, status => 400);
        }
        my $summary = $c->claude_client->summarize_logs($logs, $from, $to);
        $c->render(json => $summary);
    });
}

sub _now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

1;
