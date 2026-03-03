create or replace function render_template(
  p_tmplt text,
  p_ctx jsonb,
  p_null_str text default '')
  returns text language plpgsql as $$
declare
  l_fn_name text := 'tpl_' || md5(p_tmplt);
  l_fn_decl text := 'DECLARE res text := ''''; ';
  l_fn_body text := 'BEGIN ';
  l_ret text;
  l_cursor int := 1;
  l_beg_tag int;
  l_end_tag int;
  l_chunk text;
  l_tag_content text;
  ctx jsonb := p_ctx;
begin
  if to_regproc('pg_temp.' || l_fn_name) is null then
    loop
    l_beg_tag := strpos(substr(p_tmplt, l_cursor), '<%');
    if l_beg_tag = 0 then
      l_chunk := substr(p_tmplt, l_cursor);
      if length(l_chunk) > 0 then
        l_fn_body := l_fn_body || ' res := concat(res, '
          || quote_literal(l_chunk) || ');';
      end if;
      exit;
    end if;

    l_beg_tag := l_cursor + l_beg_tag - 1;
    if l_beg_tag > l_cursor then
      l_chunk := substr(p_tmplt, l_cursor, l_beg_tag - l_cursor);
      l_fn_body := l_fn_body || ' res := concat(res, '
        || quote_literal(l_chunk) || ');';
    end if;

    l_end_tag := strpos(substr(p_tmplt, l_beg_tag), '%>');
    if l_end_tag = 0 then
      raise exception 'Unclosed tag at %', l_beg_tag;
    end if;
    l_end_tag := l_beg_tag + l_end_tag - 1;

    l_tag_content := substr(p_tmplt, l_beg_tag, l_end_tag - l_beg_tag + 2);

    if left(l_tag_content, 3) = '<%=' then
      l_fn_body := l_fn_body
        || ' res := concat(res, COALESCE(('
        || substring(l_tag_content from 4 for length(l_tag_content)-5)
        || ')::text, p_null_str));';

    else
      l_fn_body := l_fn_body
        || substring(l_tag_content from 3 for length(l_tag_content)-4);
    end if;

    l_cursor := l_end_tag + 2;
    end loop;

    l_fn_body := l_fn_body || 'RETURN res; END;';

    execute 'CREATE OR REPLACE FUNCTION pg_temp.'
      || quote_ident(l_fn_name) || '(ctx jsonb, p_null_str text) '
      || 'RETURNS text LANGUAGE plpgsql AS '
      || quote_literal(l_fn_decl || l_fn_body);
  end if;

  execute 'SELECT pg_temp.' || quote_ident(l_fn_name) || '($1, $2)'
    into l_ret
    using ctx, p_null_str;

  return l_ret;
end;
$$;
