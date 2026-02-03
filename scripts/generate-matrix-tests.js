#!/usr/bin/env node
/**
 * Programmatic Test Matrix Generator
 *
 * Parses SPEC_COMPLIANCE.md and generates SQL test cases automatically.
 * If the spec is updated, tests can be regenerated to maintain sync.
 *
 * Usage:
 *   node scripts/generate-matrix-tests.js > tests/matrix/test_generated_matrix.sql
 *   # Or with npm:
 *   npm run generate:matrix-tests
 *
 * Output:
 *   - SQL test file with assertions for every ✅ cell in the matrix
 *   - SQL rejection tests for every 🚫 cell in the matrix
 */

// Feature matrix extracted from SPEC_COMPLIANCE.md
// This is the source of truth - update here when spec changes
const FEATURE_MATRIX = {
  // Core Modifiers - all frequencies support these
  COUNT: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  UNTIL: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  INTERVAL: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },

  // Date Filters
  BYDAY: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  // RFC 5545: BYDAY with ordinals only valid with MONTHLY/YEARLY
  'BYDAY_ordinal': {
    DAILY: '🚫', WEEKLY: '🚫', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '🚫', MINUTELY: '🚫', SECONDLY: '🚫'
  },
  BYMONTHDAY: {
    DAILY: '✅', WEEKLY: '🚫', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  'BYMONTHDAY_negative': {
    DAILY: '✅', WEEKLY: '🚫', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  BYMONTH: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  // RFC 5545: BYYEARDAY MUST NOT be specified with DAILY, WEEKLY, or MONTHLY
  BYYEARDAY: {
    DAILY: '🚫', WEEKLY: '🚫', MONTHLY: '🚫', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  'BYYEARDAY_negative': {
    DAILY: '🚫', WEEKLY: '🚫', MONTHLY: '🚫', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  BYWEEKNO: {
    DAILY: '🚫', WEEKLY: '🚫', MONTHLY: '🚫', YEARLY: '✅',
    HOURLY: '🚫', MINUTELY: '🚫', SECONDLY: '🚫'
  },

  // Week Configuration
  WKST: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },

  // Time Filters
  BYHOUR: {
    DAILY: '✅', WEEKLY: '🚫', MONTHLY: '🚫', YEARLY: '🚫',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  BYMINUTE: {
    DAILY: '✅', WEEKLY: '🚫', MONTHLY: '🚫', YEARLY: '🚫',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },
  BYSECOND: {
    DAILY: '✅', WEEKLY: '🚫', MONTHLY: '🚫', YEARLY: '🚫',
    HOURLY: '✅', MINUTELY: '✅', SECONDLY: '✅'
  },

  // Position Selectors
  BYSETPOS: {
    DAILY: '✅', WEEKLY: '✅', MONTHLY: '✅', YEARLY: '✅',
    HOURLY: '🚫', MINUTELY: '🚫', SECONDLY: '🚫'
  }
};

// Test case templates for each feature
const TEST_TEMPLATES = {
  COUNT: (freq) => ({
    rrule: `FREQ=${freq};COUNT=5`,
    dtstart: '2025-01-01 10:00:00',
    expectedCount: 5,
    description: `${freq} with COUNT=5`
  }),

  UNTIL: (freq) => ({
    rrule: `FREQ=${freq};UNTIL=20250131T235959Z`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with UNTIL`
  }),

  INTERVAL: (freq) => ({
    rrule: `FREQ=${freq};INTERVAL=2;COUNT=5`,
    dtstart: '2025-01-01 10:00:00',
    expectedCount: 5,
    description: `${freq} with INTERVAL=2`
  }),

  BYDAY: (freq) => ({
    rrule: freq === 'YEARLY' ? `FREQ=${freq};BYMONTH=1;BYDAY=MO;COUNT=5` : `FREQ=${freq};BYDAY=MO,WE,FR;COUNT=10`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with BYDAY`
  }),

  BYDAY_ordinal: (freq) => {
    // BYDAY ordinals are only valid with MONTHLY/YEARLY (RFC 5545)
    return {
      rrule: freq === 'YEARLY' ? `FREQ=${freq};BYMONTH=1;BYDAY=2MO;COUNT=5` : `FREQ=${freq};BYDAY=2TU;COUNT=5`,
      dtstart: '2025-01-01 10:00:00',
      minCount: 1,
      description: `${freq} with BYDAY ordinal (2MO/2TU)`
    };
  },

  BYMONTHDAY: (freq) => ({
    rrule: `FREQ=${freq};BYMONTHDAY=15;COUNT=5`,
    dtstart: '2025-01-15 10:00:00',
    minCount: 1,
    description: `${freq} with BYMONTHDAY=15`
  }),

  BYMONTHDAY_negative: (freq) => ({
    rrule: `FREQ=${freq};BYMONTHDAY=-1;COUNT=5`,
    dtstart: '2025-01-31 10:00:00',
    minCount: 1,
    description: `${freq} with BYMONTHDAY=-1 (last day)`
  }),

  BYMONTH: (freq) => ({
    rrule: `FREQ=${freq};BYMONTH=1,6;COUNT=10`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with BYMONTH=1,6`
  }),

  BYYEARDAY: (freq) => {
    // For sub-day frequencies, start on or near the target day to avoid iteration limits
    const isSubday = ['HOURLY', 'MINUTELY', 'SECONDLY'].includes(freq);
    return {
      rrule: `FREQ=${freq};BYYEARDAY=100;COUNT=5`,
      dtstart: isSubday ? '2025-04-10 00:00:00' : '2025-01-01 10:00:00',  // Day 100 = April 10
      minCount: 1,
      description: `${freq} with BYYEARDAY=100`
    };
  },

  BYYEARDAY_negative: (freq) => ({
    rrule: `FREQ=${freq};BYYEARDAY=-1;COUNT=5`,
    dtstart: '2025-12-31 10:00:00',  // Start on target day for all frequencies
    minCount: 1,
    description: `${freq} with BYYEARDAY=-1 (last day of year)`
  }),

  BYWEEKNO: (freq) => ({
    rrule: `FREQ=${freq};BYWEEKNO=10;COUNT=5`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with BYWEEKNO=10`
  }),

  WKST: (freq) => ({
    rrule: `FREQ=${freq};WKST=SU;COUNT=5`,
    dtstart: '2025-01-01 10:00:00',
    expectedCount: 5,
    description: `${freq} with WKST=SU`
  }),

  BYHOUR: (freq) => ({
    rrule: `FREQ=${freq};BYHOUR=9,12,17;COUNT=15`,
    dtstart: '2025-01-01 09:00:00',
    minCount: 1,
    description: `${freq} with BYHOUR=9,12,17`
  }),

  BYMINUTE: (freq) => ({
    rrule: `FREQ=${freq};BYMINUTE=0,30;COUNT=10`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with BYMINUTE=0,30`
  }),

  BYSECOND: (freq) => ({
    rrule: `FREQ=${freq};BYSECOND=0,30;COUNT=10`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with BYSECOND=0,30`
  }),

  BYSETPOS: (freq) => ({
    rrule: freq === 'YEARLY'
      ? `FREQ=${freq};BYMONTH=1;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10`
      : `FREQ=${freq};BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1,-1;COUNT=10`,
    dtstart: '2025-01-01 10:00:00',
    minCount: 1,
    description: `${freq} with BYSETPOS=1,-1`
  })
};

// Error patterns for rejection tests
const REJECTION_PATTERNS = {
  BYMONTHDAY: '%BYMONTHDAY cannot be used with FREQ=WEEKLY%',
  BYMONTHDAY_negative: '%BYMONTHDAY cannot be used with FREQ=WEEKLY%',
  BYWEEKNO: '%BYWEEKNO can only be used with FREQ=YEARLY%',
  BYYEARDAY: '%BYYEARDAY cannot be used with FREQ=%',
  BYYEARDAY_negative: '%BYYEARDAY cannot be used with FREQ=%',
  BYDAY_ordinal: '%BYDAY with ordinal%can only be used with FREQ=MONTHLY or FREQ=YEARLY%',
  BYHOUR: '%BYHOUR%not supported with FREQ=%',
  BYMINUTE: '%BYMINUTE%not supported with FREQ=%',
  BYSECOND: '%BYSECOND%not supported with FREQ=%',
  BYSETPOS: '%BYSETPOS%not supported%'
};

// Frequencies
const STANDARD_FREQS = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const SUBDAY_FREQS = ['HOURLY', 'MINUTELY', 'SECONDLY'];

function generateHeader() {
  return `/**
 * AUTO-GENERATED TEST FILE
 *
 * Generated by: scripts/generate-matrix-tests.js
 * Generated at: ${new Date().toISOString()}
 *
 * DO NOT EDIT MANUALLY - regenerate with:
 *   node scripts/generate-matrix-tests.js > tests/matrix/test_generated_matrix.sql
 *
 * This file contains systematic tests for every cell in SPEC_COMPLIANCE.md.
 * Tests are grouped by feature and frequency.
 */

\\set ON_ERROR_STOP on
\\set ECHO all

SET timezone = 'UTC';

\\if :{?rrule_install}
\\i :rrule_install
\\else
DROP SCHEMA IF EXISTS rrule CASCADE;
CREATE SCHEMA IF NOT EXISTS rrule;
\\i src/rrule.sql
\\endif

SET search_path = public;

BEGIN;

\\i tests/helpers.sql

-- Detect if subday is installed
CREATE TEMP TABLE test_config AS
SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'hourly_set'
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'rrule')
) AS subday_installed;

\\echo ''
\\echo '====================================================================='
\\echo 'AUTO-GENERATED SPEC COMPLIANCE MATRIX TESTS'
\\echo '====================================================================='
\\echo ''
`;
}

function generateAcceptanceTest(feature, freq, template) {
  const testId = `matrix-${freq}-${feature}`.toLowerCase().replace(/_/g, '-');

  if (template.expectedCount !== undefined) {
    return `
-- ${template.description}
SELECT assert_equals('${testId}', '${template.expectedCount}',
    (SELECT COUNT(*)::TEXT FROM rrule."all"('${template.rrule}', '${template.dtstart}'::TIMESTAMP)));
`;
  } else {
    return `
-- ${template.description}
SELECT assert_true('${testId}',
    (SELECT COUNT(*) >= ${template.minCount} FROM rrule."all"('${template.rrule}', '${template.dtstart}'::TIMESTAMP)));
`;
  }
}

function generateRejectionTest(feature, freq, template) {
  const testId = `reject-${freq}-${feature}`.toLowerCase().replace(/_/g, '-');
  const pattern = REJECTION_PATTERNS[feature] || `%${feature}%not%${freq}%`;

  return `
-- ${freq} with ${feature} should be rejected
SELECT assert_rrule_rejected('${testId}',
    '${template.rrule}',
    '${pattern}');
`;
}

function generateSubdayConditionalTest(feature, freq, template, status) {
  const testId = status === '✅'
    ? `matrix-${freq}-${feature}`.toLowerCase().replace(/_/g, '-')
    : `reject-${freq}-${feature}`.toLowerCase().replace(/_/g, '-');

  if (status === '✅') {
    return `
-- ${template.description} (subday-only)
DO $$
DECLARE
    result TEXT;
    cnt INT;
BEGIN
    IF (SELECT subday_installed FROM test_config) THEN
        SELECT COUNT(*) INTO cnt FROM rrule."all"('${template.rrule}', '${template.dtstart}'::TIMESTAMP);
        IF cnt >= ${template.minCount || 1} THEN
            RAISE NOTICE 'PASS [${testId}]';
        ELSE
            RAISE EXCEPTION 'FAIL [${testId}]: Expected at least ${template.minCount || 1} results, got %', cnt;
        END IF;
    ELSE
        RAISE NOTICE 'SKIP [${testId}]: Subday not installed';
    END IF;
END $$;
`;
  } else {
    const pattern = REJECTION_PATTERNS[feature] || `%${feature}%not%`;
    return `
-- ${freq} with ${feature} should be rejected
DO $$
DECLARE
    result TIMESTAMP[];
    err_msg TEXT;
BEGIN
    IF (SELECT subday_installed FROM test_config) THEN
        BEGIN
            result := (SELECT array_agg(occurrence ORDER BY occurrence)
                       FROM rrule."all"('${template.rrule}', '${template.dtstart}'::TIMESTAMP) AS occurrence);
            RAISE EXCEPTION 'FAIL [${testId}]: RRULE was accepted when it should have been rejected';
        EXCEPTION
            WHEN raise_exception THEN
                err_msg := SQLERRM;
                IF err_msg LIKE '${pattern}' THEN
                    RAISE NOTICE 'PASS [${testId}]';
                ELSE
                    RAISE EXCEPTION 'FAIL [${testId}]: Wrong error. Got: %', err_msg;
                END IF;
        END;
    ELSE
        RAISE NOTICE 'SKIP [${testId}]: Subday not installed';
    END IF;
END $$;
`;
  }
}

function generateTestsForFeature(feature) {
  const matrix = FEATURE_MATRIX[feature];
  if (!matrix) return '';

  let output = `
--------------------------------------------------------------------------------
-- FEATURE: ${feature}
--------------------------------------------------------------------------------
\\echo ''
\\echo '--- ${feature} ---'
\\echo ''
`;

  // Standard frequencies
  for (const freq of STANDARD_FREQS) {
    const status = matrix[freq];
    const templateFn = TEST_TEMPLATES[feature];
    if (!templateFn) continue;

    const template = templateFn(freq);
    if (!template) continue; // Skip null templates

    if (status === '✅') {
      output += generateAcceptanceTest(feature, freq, template);
    } else if (status === '🚫') {
      output += generateRejectionTest(feature, freq, template);
    }
  }

  // Sub-day frequencies (conditional)
  for (const freq of SUBDAY_FREQS) {
    const status = matrix[freq];
    const templateFn = TEST_TEMPLATES[feature];
    if (!templateFn) continue;

    const template = templateFn(freq);
    if (!template) continue;

    output += generateSubdayConditionalTest(feature, freq, template, status);
  }

  return output;
}

function generateFooter() {
  return `

\\echo ''
\\echo '====================================================================='
\\echo 'AUTO-GENERATED SPEC COMPLIANCE MATRIX TESTS COMPLETE'
\\echo '====================================================================='

ROLLBACK;
`;
}

function main() {
  let output = generateHeader();

  for (const feature of Object.keys(FEATURE_MATRIX)) {
    output += generateTestsForFeature(feature);
  }

  output += generateFooter();

  console.log(output);
}

main();
