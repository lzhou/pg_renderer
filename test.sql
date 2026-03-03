-- 0. Clean up
DROP VIEW IF EXISTS test_data;
DROP TABLE IF EXISTS render_log;

-- 1. Setup Dummy Data
CREATE TEMP VIEW test_data AS
SELECT '{"title": "Complex Test", "items": [{"id": 1, "val": 100}, {"id": 2, "val": 200}]}'::jsonb AS ctx;

-- =========================================================
-- TEST 1: The "Sub-Block" (Math & Logic)
-- =========================================================
-- Challenge: Using local variables for calculations.
SELECT '--- Test 1: Sub-Blocks ---' as test_name;
SELECT render_template(
    '<h3>Math Result</h3>
     <%
        DECLARE
            r record;
            tax_rate numeric := 0.15;
            total numeric := 0;
            net_price numeric;
        BEGIN
            FOR r IN SELECT * FROM jsonb_array_elements(ctx->''items'') LOOP
                total := total + (r.value->>''val'')::numeric;
            END LOOP;

            net_price := total * (1 + tax_rate);

            res := res || ''<p>Net Total (w/ Tax): $'' || net_price || ''</p>'';
        END;
     %>',
    ctx
) FROM test_data;


-- =========================================================
-- TEST 2: Raw SQL with CTEs
-- =========================================================
-- Challenge: Custom column names (no ".value" wrapper).
SELECT '--- Test 2: CTEs & Raw SQL ---' as test_name;
SELECT render_template(
    '<ul>
     <%
        DECLARE
           r record;
        BEGIN
           FOR r IN
               WITH calculated_data AS (
                   SELECT
                       (value->>''val'')::int * 10 as super_val,
                       value->>''id'' as id
                   FROM jsonb_array_elements(ctx->''items'')
                   WHERE (value->>''val'')::int > 150
               )
               SELECT * FROM calculated_data
           LOOP
     %>
        <!-- Accessing custom columns "id" and "super_val" directly -->
        <li>High Value ID <%= r.id %>: <%= r.super_val %></li>
     <%
           END LOOP;
        END;
     %>
     </ul>',
    ctx
) FROM test_data;


-- =========================================================
-- TEST 3: Side Effects (Logging)
-- =========================================================
-- Challenge: IF/ELSE syntax and database writes.
CREATE TEMP TABLE render_log (msg text);

SELECT '--- Test 3: Side Effects ---' as test_name;
SELECT render_template(
    'Status:
     <% IF (ctx->>''title'') IS NOT NULL THEN %>
        Logged
        <%
           INSERT INTO render_log VALUES (''Rendered at '' || now());
        %>
     <% ELSE %>
        Not Logged
     <% END IF; %> ',
    ctx
) FROM test_data;

SELECT * FROM render_log;


-- =========================================================
-- TEST 4: Formatting & Nesting
-- =========================================================
-- Challenge: Mixing standard SQL functions inside the template.
SELECT '--- Test 4: Nesting & Format ---' as test_name;
SELECT render_template(
    '<table>
     <%
        DECLARE r record;
        BEGIN
          FOR r IN SELECT * FROM jsonb_array_elements(ctx->''items'') LOOP
     %>
       <tr>
         <!-- Using standard SQL string functions -->
         <td><%= upper(''id-'') || lpad(r.value->>''id'', 3, ''0'') %></td>
         <td>
           <% IF (r.value->>''val'')::int > 150 THEN %>
              <b>Big</b>
           <% ELSE %>
              <small>Small</small>
           <% END IF; %>
         </td>
       </tr>
     <%
          END LOOP;
        END;
     %>
     </table>',
    ctx
) FROM test_data;


-- =========================================================
-- TEST 5: The "Deep Traverse" (Nested Loops)
-- =========================================================
-- Challenge: Multiple loop variables (unit, tag) in one block.
SELECT '--- Test 5: Nested Loops ---' as test_name;
SELECT render_template(
    '
    <div class="report">
      <h1><%= ctx->''org''->>''name'' %></h1>

      <ul>
      <%
         DECLARE
            unit record;
            tag record;
         BEGIN
            FOR unit IN SELECT * FROM jsonb_array_elements(ctx->''units'') LOOP
      %>
        <li>
           <strong>Unit: <%= unit.value->>''id'' %></strong>
           <ul>
             <%
                -- Nested Loop: Uses "unit" from the outer loop
                FOR tag IN SELECT * FROM jsonb_array_elements(unit.value->''tags'') LOOP
             %>
                <li>Tag: <%= tag.value %></li>
             <% END LOOP; %>
           </ul>
        </li>
      <%
            END LOOP;
         END;
      %>
      </ul>
    </div>
    ',
    '{
       "org": { "name": "Massive Dynamic" },
       "units": [
          { "id": "U-101", "tags": ["alpha", "beta"] },
          { "id": "U-202", "tags": ["legacy"] }
       ]
    }'::jsonb
);
