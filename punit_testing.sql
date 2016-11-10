CREATE OR REPLACE PACKAGE PUNIT_TESTING IS
  PROCEDURE run_tests(package_name STRING);
  PROCEDURE disable_test(reason string);
  PROCEDURE assert_equals(expected INT, actual INT);
END PUNIT_TESTING;
/
CREATE OR REPLACE PACKAGE BODY PUNIT_TESTING IS
  assertion_error EXCEPTION;
  PRAGMA EXCEPTION_INIT(assertion_error, -20101);
  disabled_test EXCEPTION;
  PRAGMA EXCEPTION_INIT(disabled_test, -20102);

  PROCEDURE disable_test(reason string) IS
    BEGIN
      raise_application_error(-20102, reason);
    END disable_test;

  PROCEDURE assert_equals(expected INT, actual INT) IS
      owner_name VARCHAR2(30);
      caller_name VARCHAR2(30);
      line_number NUMBER;
      caller_type VARCHAR2(100);
      source_line ALL_SOURCE.TEXT%TYPE;
    BEGIN
      IF (expected = actual) THEN
        RETURN;
      END IF;

      OWA_UTIL.who_called_me(owner_name, caller_name, line_number, caller_type);
      SELECT text
        INTO source_line
        FROM ALL_SOURCE
        WHERE name = caller_name
        AND type = 'PACKAGE BODY'
        AND line = line_number;

      raise_application_error(-20101, 'Expected: ' || expected || '; got: ' || actual || ' at ' || caller_name || '#l' || line_number || ': ' || trim(source_line));
    END assert_equals;

  FUNCTION to_hundreds_of_second(newer timestamp, older timestamp)
    RETURN string IS
      diff number;
    BEGIN
        SELECT (extract(second from newer) - extract(second from older)) * 1000 ms
          INTO diff
          FROM DUAL;
        RETURN to_char(diff / 100, 'FM990.00');
    END to_hundreds_of_second;

  PROCEDURE run_tests(package_name string) IS
      start_time timestamp  := systimestamp;
      run int := 0;
      passed int := 0;
      failed int := 0;
      errored int := 0;
      skipped int := 0;
    BEGIN
      DBMS_OUTPUT.put_line('Running ' || package_name);
      FOR p IN (SELECT procedure_name
          FROM ALL_PROCEDURES
          WHERE object_name = package_name
          AND procedure_name LIKE 'TEST_%')
        LOOP
          run := run + 1;
          BEGIN
            EXECUTE IMMEDIATE 'BEGIN ' || package_name || '.' || p.procedure_name || '; END;';
            passed := passed + 1;
            DBMS_OUTPUT.put_line(unistr('\2713') || ' ' || p.procedure_name || ' passed.');
          EXCEPTION
            WHEN disabled_test THEN
              skipped := skipped + 1;
              DBMS_OUTPUT.put_line('- ' || p.procedure_name || ' skipped: ' || SQLERRM);
            WHEN assertion_error THEN
              failed := failed + 1;
              DBMS_OUTPUT.put_line(unistr('\2717') || ' ' || p.procedure_name || ' failed: ' || SQLERRM);
            WHEN OTHERS THEN
              errored := errored + 1;
              DBMS_OUTPUT.put_line('? ' || p.procedure_name || ' errored: ' || SQLERRM);
              DBMS_OUTPUT.put_line(DBMS_UTILITY.format_error_backtrace());
          END;
        END LOOP;
        DBMS_OUTPUT.put_line('Tests run: ' || run || ', Failures: ' || failed || ', Errors: ' || errored || ', Skipped: ' || skipped || ', Time elapsed: ' || to_hundreds_of_second(systimestamp, start_time) || ' sec - in ' || package_name);
      END run_tests;
END PUNIT_TESTING;
/
