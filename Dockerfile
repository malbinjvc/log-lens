FROM perl:5.40-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN cpanm --notest Mojolicious

FROM perl:5.40-slim

COPY --from=builder /usr/local/lib/perl5 /usr/local/lib/perl5
COPY --from=builder /usr/local/share/perl5 /usr/local/share/perl5

RUN groupadd -r loglens && useradd -r -g loglens -m loglens

WORKDIR /app

COPY lib/ lib/
COPY script/ script/
COPY t/ t/

RUN chmod +x script/log_lens

RUN chown -R loglens:loglens /app

USER loglens

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD perl -e 'use Mojo::UserAgent; my $ua = Mojo::UserAgent->new; my $tx = $ua->get("http://localhost:8080/health"); exit($tx->result->is_success ? 0 : 1)'

CMD ["perl", "script/log_lens", "daemon", "-l", "http://*:8080"]
