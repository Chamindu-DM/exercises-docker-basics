#!/usr/bin/env bash
# Verifies exercise 1.16: 1_16/answer exists, contains a URL that actually
# responds, and contains a textual description of what was done (i.e. more
# than just the bare URL).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSWER_FILE="$REPO_ROOT/1_16/answer"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

[ -f "$ANSWER_FILE" ] || fail "1_16/answer not found"
pass "1_16/answer exists"

CONTENT="$(cat "$ANSWER_FILE")"
[ -n "$(echo "$CONTENT" | tr -d '[:space:]')" ] || fail "1_16/answer is empty"
pass "1_16/answer is not empty"

URL="$(echo "$CONTENT" | grep -oE 'https?://[^[:space:])"]+' | head -n 1)"
[ -n "$URL" ] || fail "1_16/answer does not contain a URL"
pass "1_16/answer contains a URL: $URL"

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 15 "$URL")"
[ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ] \
  || fail "URL \"$URL\" did not respond"
[ "$HTTP_CODE" -lt 400 ] \
  || fail "URL \"$URL\" responded with an error (HTTP $HTTP_CODE)"
pass "URL \"$URL\" responds (HTTP $HTTP_CODE)"

DESCRIPTION="$(echo "$CONTENT" | sed -E 's#https?://[^[:space:])"]+##g' | tr -d '[:space:]')"
DESC_LEN="${#DESCRIPTION}"
[ "$DESC_LEN" -ge 20 ] \
  || fail "1_16/answer has no meaningful textual description alongside the URL (only $DESC_LEN non-whitespace chars outside the URL)"
pass "1_16/answer contains a textual description ($DESC_LEN non-whitespace chars outside the URL)"

DESCRIPTION_TEXT="$(echo "$CONTENT" | sed -E 's#https?://[^[:space:])"]+##g')"
DESCRIPTION_LOWER="$(echo "$DESCRIPTION_TEXT" | tr '[:upper:]' '[:lower:]')"

# Rudimentary language check: look for common Finnish or English stopwords.
FI_WORDS='\b(ja|on|olen|olin|tein|deployasin|se|toimii|käytin|jossa|joka|mikä|sovellus|palvelin|kontti|kontissa|pilvipalvelu|pilveen)\b'
EN_WORDS='\b(the|and|is|was|deployed|used|running|application|server|container|cloud|this|with|works|link|app)\b'

FI_HITS="$(echo "$DESCRIPTION_LOWER" | grep -oE "$FI_WORDS" | wc -l | tr -d '[:space:]')"
EN_HITS="$(echo "$DESCRIPTION_LOWER" | grep -oE "$EN_WORDS" | wc -l | tr -d '[:space:]')"

if [ "$FI_HITS" -ge 2 ]; then
  pass "1_16/answer description looks like Finnish ($FI_HITS matched Finnish stopwords)"
elif [ "$EN_HITS" -ge 2 ]; then
  pass "1_16/answer description looks like English ($EN_HITS matched English stopwords)"
else
  fail "1_16/answer description does not look like Finnish or English text (found $FI_HITS Finnish and $EN_HITS English stopword matches) -- write a real description of what you did"
fi

echo "All tests passed"
