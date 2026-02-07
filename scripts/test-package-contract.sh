#!/bin/bash

set -e

echo "Running package SQL export contract tests..."
node tests/package/test_sql_exports.js
