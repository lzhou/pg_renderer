
CREATE OR REPLACE FUNCTION render_template(template_text text, ctx jsonb)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    tpl_hash text := md5(template_text);
    func_name text := 'tpl_' || tpl_hash;

    fn_decl text := 'DECLARE res text := ''''; ';
    fn_body text := 'BEGIN ';
    final_output text;

    cursor int := 1;
    start_tag int;
    end_tag int;
    chunk text;
    clean_chunk text; -- Holds the normalized logic
    tag_content text;

    loop_var text;
    declared_vars text[] := ARRAY[]::text[];
BEGIN
    IF to_regproc('pg_temp.' || func_name) IS NULL THEN

        LOOP
            -- 1. Find Start "<%"
            start_tag := strpos(substr(template_text, cursor), '<%');

            IF start_tag = 0 THEN
                chunk := substr(template_text, cursor);
                IF length(chunk) > 0 THEN
                    fn_body := fn_body || 'res := res || ' || quote_literal(chunk) || ';';
                END IF;
                EXIT;
            END IF;

            start_tag := cursor + start_tag - 1;

            -- 2. Flush Text Before Tag
            IF start_tag > cursor THEN
                chunk := substr(template_text, cursor, start_tag - cursor);
                fn_body := fn_body || 'res := res || ' || quote_literal(chunk) || ';';
            END IF;

            -- 3. Find End "%>"
            end_tag := strpos(substr(template_text, start_tag), '%>');
            IF end_tag = 0 THEN RAISE EXCEPTION 'Unclosed tag at %', start_tag; END IF;
            end_tag := start_tag + end_tag - 1;

            tag_content := substr(template_text, start_tag, end_tag - start_tag + 2);

            -- === INTELLIGENT TRANSPILE ===

            -- Case A: Output (<%=)
            IF left(tag_content, 3) = '<%=' THEN
                fn_body := fn_body
                    || 'res := res || coalesce(('
                    || substring(tag_content from 4 for length(tag_content)-5)
                    || ')::text, '''');';

            -- Case B: Logic (<%)
            ELSE
                chunk := substring(tag_content from 3 for length(tag_content)-4);

                -- STEP 1: Normalize Input (Remove trailing ; and space)
                -- This ensures <% END LOOP; %> and <% END LOOP %> are treated identically
                clean_chunk := regexp_replace(chunk, '[\s;]+$', '');
                clean_chunk := trim(clean_chunk);

                -- STEP 2: Variable Auto-Discovery
                loop_var := (regexp_match(clean_chunk, 'FOR\s+([a-zA-Z0-9_]+)\s+IN', 'i'))[1];
                IF loop_var IS NOT NULL THEN
                    IF NOT (declared_vars @> ARRAY[loop_var]) THEN
                        fn_decl := fn_decl || loop_var || ' record; ';
                        declared_vars := declared_vars || loop_var;
                    END IF;

                    -- Smart Wrapper (Only if not already raw SQL)
                    IF clean_chunk !~* 'SELECT' AND clean_chunk !~* 'jsonb_array_elements' THEN
                        IF clean_chunk ~* 'FOR\s+(\w+)\s+IN\s+(.+?)\s+LOOP' THEN
                            clean_chunk := regexp_replace(
                                clean_chunk,
                                'FOR\s+(\w+)\s+IN\s+(.+?)\s+LOOP',
                                'FOR \1 IN SELECT * FROM jsonb_array_elements(\2) LOOP',
                                'i'
                            );
                        END IF;
                    END IF;
                END IF;

                -- STEP 3: Smart Semicolon Injection
                -- Logic: Block STARTERS (THEN, LOOP, DO, BEGIN) get space.
                --        Block ENDERS (END LOOP) and statements get semicolon.
                --        CRITICAL: We must distinguish "LOOP" from "END LOOP"

                IF clean_chunk ~* 'THEN$'
                   OR clean_chunk ~* 'ELSE$'
                   OR clean_chunk ~* 'DO$'
                   OR clean_chunk ~* 'BEGIN$'
                   -- Matches "LOOP" but NOT "END LOOP"
                   OR (clean_chunk ~* 'LOOP$' AND clean_chunk !~* 'END\s+LOOP$') THEN

                     fn_body := fn_body || clean_chunk || ' ';
                ELSE
                     fn_body := fn_body || clean_chunk || ';';
                END IF;
            END IF;

            cursor := end_tag + 2;
        END LOOP;

        fn_body := fn_body || 'RETURN res; END;';

        EXECUTE 'CREATE OR REPLACE FUNCTION pg_temp.' || quote_ident(func_name) || '(ctx jsonb) '
             || 'RETURNS text LANGUAGE plpgsql AS '
             || quote_literal(fn_decl || fn_body);
    END IF;

    EXECUTE 'SELECT pg_temp.' || quote_ident(func_name) || '($1)' INTO final_output USING ctx;

    RETURN final_output;
END;
$$;
