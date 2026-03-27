package LogLens::Models::Store;
use Mojo::Base -base, -signatures;

has 'logs'     => sub { {} };
has 'next_id'  => sub { 1 };

sub next_log_id ($self) {
    my $id = $self->next_id;
    $self->next_id($id + 1);
    return $id;
}

package LogLens::Models::LogEntry;
use Mojo::Base -base, -signatures;

sub new_from_data ($class, %args) {
    my $id        = $args{id} // 0;
    my $data      = $args{data} // {};
    my $timestamp = $data->{timestamp} // _now();
    my $source    = $data->{source}    // 'unknown';
    my $level     = lc($data->{level}  // 'info');
    my $message   = $data->{message}   // '';
    my $metadata  = $data->{metadata}  // {};

    return {
        id        => $id,
        timestamp => $timestamp,
        source    => $source,
        level     => $level,
        message   => $message,
        metadata  => $metadata,
    };
}

sub _now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

package LogLens::Models::Pattern;
use Mojo::Base -base, -signatures;

sub new_pattern ($class, %args) {
    return {
        id          => $args{id}          // 0,
        regex       => $args{regex}       // '',
        description => $args{description} // '',
        frequency   => $args{frequency}   // 0,
        severity    => $args{severity}    // 'info',
        examples    => $args{examples}    // [],
    };
}

package LogLens::Models::Anomaly;
use Mojo::Base -base, -signatures;

sub new_anomaly ($class, %args) {
    return {
        id          => $args{id}          // 0,
        log_ids     => $args{log_ids}     // [],
        type        => $args{type}        // 'unknown',
        description => $args{description} // '',
        score       => $args{score}       // 0.0,
    };
}

package LogLens::Models;
1;
