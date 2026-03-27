package LogLens::Services::LogService;
use Mojo::Base -base, -signatures;
use LogLens::Models;

has 'store';

sub create ($self, $data) {
    my $id    = $self->store->next_log_id;
    my $entry = LogLens::Models::LogEntry->new_from_data(id => $id, data => $data);
    $self->store->logs->{$id} = $entry;
    return $entry;
}

sub get ($self, $id) {
    return $self->store->logs->{$id};
}

sub delete ($self, $id) {
    my $entry = $self->store->logs->{$id};
    return undef unless $entry;
    delete $self->store->logs->{$id};
    return $entry;
}

sub list ($self, %filters) {
    my $level  = $filters{level};
    my $source = $filters{source};

    my @logs = sort { $a->{id} <=> $b->{id} } values %{ $self->store->logs };

    if ($level) {
        $level = lc $level;
        @logs = grep { $_->{level} eq $level } @logs;
    }
    if ($source) {
        @logs = grep { $_->{source} eq $source } @logs;
    }

    return \@logs;
}

sub stats ($self) {
    my @logs = values %{ $self->store->logs };
    my $total = scalar @logs;

    my %by_level;
    my %by_source;
    my %by_hour;

    for my $log (@logs) {
        $by_level{ $log->{level} }++;
        $by_source{ $log->{source} }++;

        if ($log->{timestamp} =~ /T(\d{2}):/) {
            $by_hour{$1}++;
        }
    }

    return {
        total          => $total,
        by_level       => \%by_level,
        by_source      => \%by_source,
        time_distribution => \%by_hour,
    };
}

package LogLens::Services::PatternService;
use Mojo::Base -base, -signatures;

has 'store';

sub discover ($self, $logs) {
    return [] unless $logs && @$logs;

    my %prefix_count;
    my %prefix_examples;
    my %prefix_levels;

    for my $log (@$logs) {
        my $msg = $log->{message} // '';
        # Extract prefix: first word or bracket-enclosed prefix
        my $prefix;
        if ($msg =~ /^(\[[^\]]+\])/) {
            $prefix = $1;
        } elsif ($msg =~ /^(\S+)/) {
            $prefix = $1;
        } else {
            next;
        }

        $prefix_count{$prefix}++;
        $prefix_levels{$prefix}{ $log->{level} }++;
        $prefix_examples{$prefix} //= [];
        if (scalar @{ $prefix_examples{$prefix} } < 3) {
            push @{ $prefix_examples{$prefix} }, $msg;
        }
    }

    my @patterns;
    my $pid = 1;
    for my $prefix (sort { $prefix_count{$b} <=> $prefix_count{$a} } keys %prefix_count) {
        next if $prefix_count{$prefix} < 2;

        my $escaped = quotemeta($prefix);
        my $severity = _classify_severity($prefix, $prefix_levels{$prefix});

        push @patterns, LogLens::Models::Pattern->new_pattern(
            id          => $pid++,
            regex       => "^${escaped}",
            description => "Messages starting with '$prefix' (found $prefix_count{$prefix} times)",
            frequency   => $prefix_count{$prefix},
            severity    => $severity,
            examples    => $prefix_examples{$prefix},
        );
    }

    return \@patterns;
}

sub _classify_severity ($prefix, $level_counts) {
    my $lc_prefix = lc($prefix);
    # Check prefix keywords
    return 'critical' if $lc_prefix =~ /fatal|panic|crash/;
    return 'error'    if $lc_prefix =~ /error|fail|exception/;
    return 'warning'  if $lc_prefix =~ /warn|timeout|retry/;

    # Check dominant log level
    my $max_level = '';
    my $max_count = 0;
    for my $lvl (keys %$level_counts) {
        if ($level_counts->{$lvl} > $max_count) {
            $max_count = $level_counts->{$lvl};
            $max_level = $lvl;
        }
    }

    return 'critical' if $max_level eq 'fatal';
    return 'error'    if $max_level eq 'error';
    return 'warning'  if $max_level eq 'warn' || $max_level eq 'warning';
    return 'info';
}

package LogLens::Services::AnomalyService;
use Mojo::Base -base, -signatures;

has 'store';
has 'claude_client';

sub detect ($self, $logs, $params) {
    return [] unless $logs && @$logs;

    my @anomalies;
    my $aid = 1;

    # 1. Rate spike detection: check if error rate is unusually high
    my $total       = scalar @$logs;
    my @error_logs  = grep { $_->{level} eq 'error' || $_->{level} eq 'fatal' } @$logs;
    my $error_count = scalar @error_logs;

    if ($total > 0 && $error_count / $total > 0.3) {
        push @anomalies, LogLens::Models::Anomaly->new_anomaly(
            id          => $aid++,
            log_ids     => [ map { $_->{id} } @error_logs ],
            type        => 'rate_spike',
            description => "High error rate detected: $error_count errors out of $total logs ("
                           . int($error_count / $total * 100) . "%)",
            score       => sprintf('%.2f', $error_count / $total),
        );
    }

    # 2. New error type detection: errors with unique messages
    my %error_msgs;
    for my $log (@error_logs) {
        my $key = substr($log->{message}, 0, 50);
        push @{ $error_msgs{$key} }, $log->{id};
    }
    for my $key (keys %error_msgs) {
        if (scalar @{ $error_msgs{$key} } == 1) {
            push @anomalies, LogLens::Models::Anomaly->new_anomaly(
                id          => $aid++,
                log_ids     => $error_msgs{$key},
                type        => 'new_error_type',
                description => "Unique error detected: '$key'",
                score       => 0.7,
            );
        }
    }

    # 3. Source anomaly: source that only produces errors
    my %source_levels;
    for my $log (@$logs) {
        $source_levels{ $log->{source} }{ $log->{level} }++;
    }
    for my $src (keys %source_levels) {
        my $levels = $source_levels{$src};
        my $src_total = 0;
        my $src_errors = 0;
        for my $lvl (keys %$levels) {
            $src_total += $levels->{$lvl};
            $src_errors += $levels->{$lvl} if $lvl eq 'error' || $lvl eq 'fatal';
        }
        if ($src_total >= 2 && $src_errors == $src_total) {
            my @ids = map { $_->{id} } grep { $_->{source} eq $src } @$logs;
            push @anomalies, LogLens::Models::Anomaly->new_anomaly(
                id          => $aid++,
                log_ids     => \@ids,
                type        => 'source_anomaly',
                description => "Source '$src' is producing only errors ($src_errors entries)",
                score       => 0.85,
            );
        }
    }

    # 4. Use mock Claude client for additional analysis
    my $ai_anomalies = $self->claude_client->detect_anomalies($logs);
    for my $a (@$ai_anomalies) {
        $a->{id} = $aid++;
        push @anomalies, $a;
    }

    return \@anomalies;
}

package LogLens::Services;
1;
