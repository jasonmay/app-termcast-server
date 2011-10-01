#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


MODULE = App::Termcast::Server	PACKAGE = App::Termcast::Server::Util

PROTOTYPES: DISABLE;

SV*
extract_metadata(sv)
    SV *sv
  PREINIT:
    SV *ret;
    STRLEN metadata_len;
    char *buf;
    char *cur;
    char *end;
  CODE:

    ret = &PL_sv_undef;

    if (!SvPOK(sv))
        croak("extract_metadata takes a string");

    cur = SvPVX(sv);
    end = SvEND(sv);

    buf = cur;
    if (end - cur >= 4) {
        metadata_len = 0;
        while (buf != end) {
            if (metadata_len > 0 && *buf == '\377') {
                ret = newSVpv(buf - metadata_len + 1, metadata_len - 1);
                sv_chop(sv, buf + 1);
                break;
            }
            else if (metadata_len > 0) {
                ++metadata_len;
            }
            else if (*buf == '\033'
              && *(buf + 1) == '['
              && *(buf + 2) == 'H'
              && *(buf + 3) == '\0') {
                buf += 3;
                metadata_len = 1;
            }
            ++buf;
        }
    }
    RETVAL = ret;
  OUTPUT:
    RETVAL

void
shorten(sv)
    SV *sv
  PREINIT:
    char *cur;
    char *end;
  CODE:
    if (!SvPOK(sv))
        croak("shorten takes a string");

    cur = SvPVX(sv);
    end = SvEND(sv);

    if (end - cur > 51200)
        sv_chop(sv, end - 51200);

    cur = SvPVX(sv);
    end = SvEND(sv);

    while (cur != end) {
        if (end - cur >= 7
          && *cur == '\033'
          && *(cur + 1) == '['
          && *(cur + 2) == 'H'
          && *(cur + 3) == '\033'
          && *(cur + 4) == '['
          && *(cur + 5) == '2'
          && *(cur + 6) == 'J') {
            sv_chop(sv, cur + 7);
            break;
        }
        ++cur;
    }

