defmodule AgenticAiAgent.LLM.Embeddings do
  @moduledoc """
  Behaviour for embedding providers. A batch returns embeddings in the same
  order as the input texts. The provider is also expected to report the
  model name used so we can detect dimension mismatches at query time.
  """

  @callback embed(texts :: [String.t()], opts :: keyword()) ::
              {:ok, %{model: String.t(), vectors: [[float()]]}} | {:error, term()}

  def default do
    Application.get_env(
      :agentic_ai_agent,
      :embeddings_adapter,
      AgenticAiAgent.LLM.AzureOpenAIEmbeddings
    )
  end

  def embed(texts, opts \\ []), do: default().embed(texts, opts)
end
