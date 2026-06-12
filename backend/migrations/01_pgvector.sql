-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Add embedding column to transactions table
ALTER TABLE public.transactions
ADD COLUMN embedding vector(768); -- 768 is the typical dimension for text-embedding models like text-embedding-004

-- Create a function to perform similarity search
CREATE OR REPLACE FUNCTION match_transactions (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  user_id_param uuid
)
RETURNS TABLE (
  id uuid,
  title text,
  amount numeric,
  category text,
  type text,
  created_at timestamp with time zone,
  similarity float
)
LANGUAGE sql STABLE
AS $$
  SELECT
    transactions.id,
    transactions.title,
    transactions.amount,
    transactions.category,
    transactions.type,
    transactions.created_at,
    1 - (transactions.embedding <=> query_embedding) AS similarity
  FROM transactions
  WHERE transactions.user_id = user_id_param
    AND transactions.embedding IS NOT NULL
    AND 1 - (transactions.embedding <=> query_embedding) > match_threshold
  ORDER BY transactions.embedding <=> query_embedding
  LIMIT match_count;
$$;
