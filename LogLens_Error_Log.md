# LogLens Error Log

## Project: LogLens
- **Language**: Perl 5.34.1
- **Framework**: Mojolicious 9.42
- **Date**: 2026-03-27

---

## Error 1: PERL5LIB Path Required for Mojolicious

**Error**: `Can't locate Mojolicious.pm in @INC` when running tests or app.

**Cause**: Mojolicious installed in user-local directory `~/perl5/lib/perl5` rather than system Perl paths.

**Fix**: Set `PERL5LIB=~/perl5/lib/perl5:lib` before running `prove -l t/` or `perl main.pl`.

---

## Error 2: Uninitialized $_ Warning in Clients.pm

**Error**: `Use of uninitialized value $_ in pattern match` at Clients.pm line 51.

**Cause**: Pattern matching on `$_` without explicitly assigning it in some code paths within the mock Claude client analysis function.

**Fix**: Ensured all grep/map operations explicitly set the loop variable. Warning is non-fatal and does not affect test results. 183 tests pass.

---

## Error 3: Docker Perl Module Installation

**Error**: Mojolicious and JSON::XS not found in Docker container.

**Cause**: Docker image needed CPAN modules installed during build stage.

**Fix**: Used `cpanm --notest Mojolicious JSON::XS` in Dockerfile build stage with `perl:5.40-slim` base image.

---

## Summary
- Total errors encountered: 3
- All resolved successfully
- Tests passing: 183/183
- CI status: Configured
