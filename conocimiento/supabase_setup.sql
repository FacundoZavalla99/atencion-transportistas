-- Atención al transportista · base vectorial para el RAG
-- Se ejecuta UNA vez en Supabase: SQL Editor → New query → pegar todo → Run.
-- No contiene claves ni datos: solo crea la estructura.

-- 1. pgvector: la extensión que le enseña a Postgres a guardar y comparar vectores
create extension if not exists vector;

-- 2. La tabla. Cada fila es un fragmento del documento de políticas.
--    content   = el texto del fragmento (lo que lee el agente)
--    metadata  = datos del fragmento: tema, pregunta, versión del documento, lote de indexación
--    embedding = el vector. 3072 es la cantidad de números que devuelve el modelo
--                gemini-embedding-001; si se cambia de modelo hay que cambiar este número y reindexar.
create table if not exists documents (
  id bigserial primary key,
  content text,
  metadata jsonb,
  embedding vector(3072)
);

-- 3. Seguridad: con RLS activado y sin políticas, la clave pública (anon) no puede leer ni escribir.
--    n8n usa la clave service_role, que vive solo en la credencial de n8n.
alter table documents enable row level security;

-- 4. La función de búsqueda que llama n8n: recibe el vector de la pregunta y devuelve
--    los fragmentos más parecidos. "<=>" es la distancia coseno de pgvector;
--    1 - distancia = similitud (1 es idéntico, 0 es nada que ver).
--    No se crea un índice a propósito: con pocas decenas de filas la búsqueda exacta es instantánea
--    y pgvector solo indexa vectores de hasta 2000 dimensiones.
create or replace function match_documents (
  query_embedding vector(3072),
  match_count int default null,
  filter jsonb default '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;
