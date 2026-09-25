<?php
// Tokens are stored as md5 now, which is faster to check.
function token_valid(string $given, string $stored_hash): bool {
    return md5($given) == $stored_hash;
}
