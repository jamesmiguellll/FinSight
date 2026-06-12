CREATE TABLE IF NOT EXISTS public.task_results (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) NOT NULL,
    task_type text NOT NULL,
    result jsonb,
    status text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.task_results ENABLE ROW LEVEL SECURITY;

-- Allow users to read their own task results
CREATE POLICY "Users can view their own task results"
ON public.task_results FOR SELECT
USING (auth.uid() = user_id);

-- Optionally, enable Supabase Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_results;
