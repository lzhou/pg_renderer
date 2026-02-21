-- 0. Clean up previous run
DROP VIEW IF EXISTS test_data;
DROP TABLE IF EXISTS render_log;

-- 1. Setup Dummy Data
CREATE TEMP VIEW test_data AS
SELECT '{"title": "Complex Test", "items": [{"id": 1, "val": 100}, {"id": 2, "val": 200}]}'::jsonb AS ctx;

-- =========================================================
-- TEST 1: The "Sub-Block" (Local Variables & Logic)
-- =========================================================
SELECT '--- Test 1: Sub-Blocks ---' as test_name;
SELECT render_template(
    '<h3>Math Result</h3>
     <%
        /* Start a completely isolated sub-block */
        DECLARE
            tax_rate numeric := 0.15;
            total numeric := 0;
            net_price numeric;
        BEGIN
            /* Perform math not possible in simple templates */
            /* Standard Loop -> Access via .value */
            FOR r IN SELECT * FROM jsonb_array_elements(ctx->''items'') LOOP
                total := total + (r.value->>''val'')::numeric;
            END LOOP;

            net_price := total * (1 + tax_rate);

            /* POWER MOVE: Direct write to the result buffer "res" */
            res := res || ''<p>Net Total (w/ Tax): $'' || net_price || ''</p>'';
        END;
     %>',
    ctx
) FROM test_data;


-- =========================================================
-- TEST 2: Raw SQL with CTEs (Fixed Column Access)
-- =========================================================
SELECT '--- Test 2: CTEs & Raw SQL ---' as test_name;
SELECT render_template(
    '<ul>
     <%
        FOR row IN
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
        <!-- CRITICAL: In Raw SQL, we defined "id" and "super_val", NOT "value" -->
        <!-- Correct: row.id -->
        <!-- Wrong:   row.value.id -->
        <li>High Value ID <%= row.id %>: <%= row.super_val %></li>
     <% END LOOP %>
     </ul>',
    ctx
) FROM test_data;


-- =========================================================
-- TEST 3: Side Effects (Logging/Inserts during Render)
-- =========================================================
CREATE TEMP TABLE render_log (msg text);

SELECT '--- Test 3: Side Effects (PERFORM) ---' as test_name;
SELECT render_template(
    'Status:
     <% IF (ctx->>''title'') IS NOT NULL THEN %>
        Logged
        <%
           -- Perform a write operation silently
           INSERT INTO render_log VALUES (''Rendered at '' || now());
        %>
     <% ELSE %>
        Not Logged
     <% END IF %>',
    ctx
) FROM test_data;

-- Verify the log was written
SELECT * FROM render_log;


-- =========================================================
-- TEST 4: Deep Nesting & String Functions
-- =========================================================
SELECT '--- Test 4: Nesting & Format ---' as test_name;
SELECT render_template(
    '<table>
     <% FOR item IN ctx->''items'' LOOP %>
       <tr>
         <!-- Using standard SQL string functions upper() and pad() -->
         <td><%= upper(''id-'') || lpad(item.value->>''id'', 3, ''0'') %></td>
         <td>
           <% IF (item.value->>''val'')::int > 150 THEN %>
              <b>Big</b>
           <% ELSE %>
              <small>Small</small>
           <% END IF %>
         </td>
       </tr>
     <% END LOOP %>
     </table>',
    ctx
) FROM test_data;

-- =========================================================
-- TEST 5: One more...
-- =========================================================
SELECT '--- Test 5: Nesting & Format ---' as test_name;
SELECT render_template(
    '
    <div class="report">
      <!-- 1. Deep Nested Key/Value Access -->
      <h1><%= ctx->''org''->>''name'' %> (<%= ctx->''org''->''meta''->>''founded'' %>)</h1>
      <p>HQ: <%= ctx->''org''->''meta''->>''hq'' %></p>

      <ul>
      <!-- 2. Outer Loop: Iterating the "Units" Array -->
      <% FOR unit IN ctx->''units'' LOOP %>
        <li>
           <strong>Unit: <%= unit.value->>''id'' %></strong>

           <!-- 3. K/V Access inside an Array Element -->
           <!-- logic: IF unit.config.active IS TRUE -->
           <% IF (unit.value->''config''->>''active'')::boolean THEN %>
               <span style="color:green">[ACTIVE - Lvl <%= unit.value->''config''->>''level'' %>]</span>
           <% ELSE %>
               <span style="color:red">[OFFLINE]</span>
           <% END IF %>

           <!-- 4. Nested Loop: Iterating the "Tags" Array inside the Unit -->
           <ul>
             <% FOR tag IN unit.value->''tags'' LOOP %>
                <!-- tag.value is a text string here -->
                <li>Tag: <%= tag.value %></li>
             <% END LOOP %>
           </ul>
        </li>
      <% END LOOP %>
      </ul>
    </div>
    ',

    '{
       "org": {
          "name": "Massive Dynamic",
          "meta": {
             "founded": 2026,
             "hq": "San Diego"
          }
       },
       "units": [
          {
             "id": "U-101",
             "config": { "active": true, "level": 5 },
             "tags": ["alpha", "beta"]
          },
          {
             "id": "U-202",
             "config": { "active": false, "level": 1 },
             "tags": ["legacy"]
          }
       ]
    }'::jsonb
) AS final_render;
