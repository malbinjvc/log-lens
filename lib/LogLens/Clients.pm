package LogLens::Clients::MockClaudeClient;
use Mojo::Base -base, -signatures;

sub analyze_logs ($self, $logs) {
    my $total = scalar @$logs;
    return { error => 'No logs provided' } unless $total;

    # Count by level
    my %level_counts;
    for my $log (@$logs) {
        $level_counts{ $log->{level} }++;
    }

    # Count error keywords in messages
    my %keyword_counts;
    my @error_keywords = qw(error fail timeout crash exception null undefined panic segfault oom);
    for my $log (@$logs) {
        my $msg = lc($log->{message} // '');
        for my $kw (@error_keywords) {
            $keyword_counts{$kw}++ if $msg =~ /\Q$kw\E/;
        }
    }

    # Extract patterns from repeated message prefixes
    my %prefix_count;
    for my $log (@$logs) {
        my $msg = $log->{message} // '';
        if ($msg =~ /^(\S+)/) {
            $prefix_count{$1}++;
        }
    }
    my @common_prefixes = sort { $prefix_count{$b} <=> $prefix_count{$a} }
                          grep { $prefix_count{$_} >= 2 }
                          keys %prefix_count;

    # Determine overall health
    my $error_rate = ($level_counts{error} // 0) + ($level_counts{fatal} // 0);
    my $health;
    if ($total > 0 && $error_rate / $total > 0.5) {
        $health = 'critical';
    } elsif ($total > 0 && $error_rate / $total > 0.2) {
        $health = 'degraded';
    } else {
        $health = 'healthy';
    }

    # Build recommendations
    my @recommendations;
    push @recommendations, "Investigate high error rate ($error_rate/$total errors)"
        if $error_rate > 0;
    push @recommendations, "Review recurring pattern: '$_'" for @common_prefixes[0..1];
    for my $kw (sort keys %keyword_counts) {
        push @recommendations, "Keyword '$kw' found $keyword_counts{$kw} time(s) - review related logs";
    }
    push @recommendations, 'No significant issues detected' unless @recommendations;

    return {
        analysis => {
            total_logs      => $total,
            level_breakdown => \%level_counts,
            error_keywords  => \%keyword_counts,
            common_prefixes => [ @common_prefixes[0..4] ],
            health_status   => $health,
        },
        recommendations => \@recommendations,
        model           => 'mock-claude-3.5',
    };
}

sub detect_anomalies ($self, $logs) {
    my @anomalies;
    return \@anomalies unless $logs && @$logs;

    # Detect repeated identical messages (potential log storm)
    my %msg_count;
    my %msg_ids;
    for my $log (@$logs) {
        my $msg = $log->{message} // '';
        $msg_count{$msg}++;
        push @{ $msg_ids{$msg} }, $log->{id};
    }

    for my $msg (keys %msg_count) {
        if ($msg_count{$msg} >= 3) {
            push @anomalies, {
                id          => 0,
                log_ids     => $msg_ids{$msg},
                type        => 'log_storm',
                description => "Repeated message detected $msg_count{$msg} times: '$msg'",
                score       => sprintf('%.2f', 0.5 + ($msg_count{$msg} / 20.0)),
            };
        }
    }

    return \@anomalies;
}

sub summarize_logs ($self, $logs, $from, $to) {
    my $total = scalar @$logs;
    return { error => 'No logs to summarize' } unless $total;

    # Group by level
    my %by_level;
    for my $log (@$logs) {
        push @{ $by_level{ $log->{level} } }, $log;
    }

    # Group by source
    my %by_source;
    for my $log (@$logs) {
        push @{ $by_source{ $log->{source} } }, $log;
    }

    # Build summary text
    my @sections;
    push @sections, "Log Summary for " . ($from // 'start') . " to " . ($to // 'now');
    push @sections, "Total entries analyzed: $total";
    push @sections, "";

    # Level breakdown
    push @sections, "Level Breakdown:";
    for my $lvl (sort keys %by_level) {
        my $count = scalar @{ $by_level{$lvl} };
        push @sections, "  - $lvl: $count entries";
    }
    push @sections, "";

    # Source breakdown
    push @sections, "Source Breakdown:";
    for my $src (sort keys %by_source) {
        my $count = scalar @{ $by_source{$src} };
        push @sections, "  - $src: $count entries";
    }
    push @sections, "";

    # Key findings
    push @sections, "Key Findings:";
    my $error_count = scalar @{ $by_level{error} // [] };
    my $fatal_count = scalar @{ $by_level{fatal} // [] };
    if ($error_count + $fatal_count > 0) {
        push @sections, "  - $error_count error(s) and $fatal_count fatal(s) detected";
    } else {
        push @sections, "  - No errors or fatal issues detected";
    }

    # Sample messages from errors
    if ($by_level{error}) {
        push @sections, "  - Sample errors:";
        my @samples = @{ $by_level{error} }[0..2];
        for my $s (grep { defined } @samples) {
            push @sections, "    * [$s->{source}] $s->{message}";
        }
    }

    return {
        summary     => join("\n", @sections),
        total_logs  => $total,
        time_range  => { from => $from // 'start', to => $to // 'now' },
        breakdown   => {
            by_level  => { map { $_ => scalar @{ $by_level{$_} } } keys %by_level },
            by_source => { map { $_ => scalar @{ $by_source{$_} } } keys %by_source },
        },
        model       => 'mock-claude-3.5',
    };
}

package LogLens::Clients;
1;
