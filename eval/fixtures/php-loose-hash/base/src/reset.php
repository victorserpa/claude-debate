<?php
function token_valid(string $given, string $stored_hash): bool {
    return password_verify($given, $stored_hash);
}
