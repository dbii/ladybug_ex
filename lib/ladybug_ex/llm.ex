defmodule LadybugEx.LLM do
  @moduledoc """
  Interface for generating text embeddings using the llm extension.

  This module provides functions for generating embeddings via external
  LLM providers like OpenAI, Google, AWS Bedrock, and others.

  ## Prerequisites

  The llm extension must be installed and loaded before using this module:

      # Install once
      LadybugEx.Extensions.install(conn, "llm")

      # Load for each connection
      LadybugEx.Extensions.load(conn, "llm")

  This module will automatically ensure the extension is loaded when calling
  its functions.

  ## Supported Providers

  - `:amazon_bedrock` - AWS Bedrock (requires AWS credentials)
  - `:google_vertex` - Google Vertex AI
  - `:google_gemini` - Google Gemini
  - `:ollama` - Local Ollama server
  - `:openai` - OpenAI API
  - `:voyageai` - Voyage AI

  ## Required Environment Variables

  Each provider requires specific environment variables:

  - OpenAI: `OPENAI_API_KEY`
  - Google Vertex: `GOOGLE_API_KEY` or service account credentials
  - Google Gemini: `GOOGLE_API_KEY`
  - AWS Bedrock: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
  - Voyage AI: `VOYAGEAI_API_KEY`
  - Ollama: None (local server)

  ## Usage Examples

      # Generate embedding with OpenAI
      {:ok, embedding} = LLM.create_embedding(conn,
        "Machine learning is fascinating",
        provider: :openai,
        model: "text-embedding-ada-002"
      )

      # Generate with specific dimensions
      {:ok, embedding} = LLM.create_embedding(conn,
        "Graph databases are powerful",
        provider: :openai,
        model: "text-embedding-3-small",
        dimensions: 512
      )

      # Use local Ollama
      {:ok, embedding} = LLM.create_embedding(conn,
        "Local embeddings",
        provider: :ollama,
        model: "nomic-embed-text",
        endpoint: "http://localhost:11434"
      )

      # Batch processing
      texts = ["Text 1", "Text 2", "Text 3"]
      embeddings = Enum.map(texts, fn text ->
        {:ok, emb} = LLM.create_embedding(conn, text, provider: :openai)
        emb
      end)
  """

  alias LadybugEx.{Connection, Extensions}

  @type provider ::
          :amazon_bedrock
          | :google_vertex
          | :google_gemini
          | :ollama
          | :openai
          | :voyageai

  @type embedding :: [float()]

  @provider_models %{
    openai: ["text-embedding-ada-002", "text-embedding-3-small", "text-embedding-3-large"],
    google_vertex: ["textembedding-gecko"],
    google_gemini: ["embedding-001"],
    amazon_bedrock: ["amazon.titan-embed-text-v1", "amazon.titan-embed-text-v2"],
    voyageai: ["voyage-2", "voyage-large-2", "voyage-code-2"],
    ollama: ["nomic-embed-text", "mxbai-embed-large", "all-minilm"]
  }

  @doc """
  Generate an embedding for the given text using an LLM provider.

  ## Options

    * `:provider` - (required) The LLM provider to use
    * `:model` - Model to use (defaults to provider's default model)
    * `:dimensions` - Embedding dimensions (provider-specific support)
    * `:region` - AWS region for Bedrock (default: us-east-1)
    * `:endpoint` - Custom endpoint URL (for Ollama or custom deployments)

  ## Examples

      # OpenAI with default model
      {:ok, embedding} = LLM.create_embedding(conn,
        "This is my text",
        provider: :openai
      )

      # OpenAI with specific model and dimensions
      {:ok, embedding} = LLM.create_embedding(conn,
        "Advanced text processing",
        provider: :openai,
        model: "text-embedding-3-large",
        dimensions: 3072
      )

      # AWS Bedrock
      {:ok, embedding} = LLM.create_embedding(conn,
        "Cloud computing",
        provider: :amazon_bedrock,
        model: "amazon.titan-embed-text-v2",
        region: "us-west-2"
      )

      # Local Ollama server
      {:ok, embedding} = LLM.create_embedding(conn,
        "Local processing",
        provider: :ollama,
        model: "nomic-embed-text",
        endpoint: "http://localhost:11434"
      )
  """
  @spec create_embedding(Connection.t(), String.t(), keyword()) ::
          {:ok, embedding()} | {:error, String.t()}
  def create_embedding(conn, text, opts)
      when is_binary(text) and is_list(opts) do
    with {:ok, params} <- validate_params(text, opts),
         :ok <- check_environment_variables(params.provider),
         :ok <- Extensions.ensure_loaded(conn, "llm") do
      query = build_embedding_query(params)

      case Connection.query(conn, query) do
        {:ok, [result | _]} ->
          {:ok, result["embedding"]}

        {:ok, []} ->
          {:error, "No embedding returned"}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Generate an embedding for the given text using an LLM provider.

  Raises an error if embedding generation fails.

  ## Examples

      embedding = LLM.create_embedding!(conn,
        "This is my text",
        provider: :openai
      )
  """
  @spec create_embedding!(Connection.t(), String.t(), keyword()) :: embedding()
  def create_embedding!(conn, text, opts) do
    case create_embedding(conn, text, opts) do
      {:ok, embedding} -> embedding
      {:error, reason} -> raise "Failed to create embedding: #{reason}"
    end
  end

  @doc """
  Generate embeddings for multiple texts in batch.

  More efficient than individual calls for some providers. Falls back
  to sequential processing if batch is not supported.

  ## Options

  Same as `create_embedding/3`

  ## Examples

      texts = ["Text 1", "Text 2", "Text 3"]
      {:ok, embeddings} = LLM.create_embeddings(conn, texts,
        provider: :openai
      )
  """
  @spec create_embeddings(Connection.t(), [String.t()], keyword()) ::
          {:ok, [embedding()]} | {:error, String.t()}
  def create_embeddings(conn, texts, opts)
      when is_list(texts) and is_list(opts) do
    with {:ok, base_params} <- validate_batch_params(texts, opts),
         :ok <- check_environment_variables(base_params.provider),
         :ok <- Extensions.ensure_loaded(conn, "llm") do
      # Process texts sequentially (batch support would require provider-specific handling)
      results =
        Enum.reduce_while(texts, {:ok, []}, fn text, {:ok, acc} ->
          case create_embedding(conn, text, opts) do
            {:ok, embedding} -> {:cont, {:ok, [embedding | acc]}}
            {:error, _} = error -> {:halt, error}
          end
        end)

      case results do
        {:ok, embeddings} -> {:ok, Enum.reverse(embeddings)}
        error -> error
      end
    end
  end

  @doc """
  Generate embeddings for multiple texts in batch.

  Raises an error if embedding generation fails.

  ## Examples

      texts = ["Text 1", "Text 2", "Text 3"]
      embeddings = LLM.create_embeddings!(conn, texts,
        provider: :openai
      )
  """
  @spec create_embeddings!(Connection.t(), [String.t()], keyword()) :: [embedding()]
  def create_embeddings!(conn, texts, opts) do
    case create_embeddings(conn, texts, opts) do
      {:ok, embeddings} -> embeddings
      {:error, reason} -> raise "Failed to create embeddings: #{reason}"
    end
  end

  @doc """
  Check if required environment variables are set for a provider.

  ## Examples

      iex> LLM.check_provider_config(:openai)
      {:ok, %{api_key_set: true}}

      iex> LLM.check_provider_config(:openai)
      {:error, "Missing environment variable: OPENAI_API_KEY"}
  """
  @spec check_provider_config(provider()) :: {:ok, map()} | {:error, String.t()}
  def check_provider_config(provider) when is_atom(provider) do
    check_environment_variables(provider)
  end

  @doc """
  Get the list of supported models for a provider.

  ## Examples

      iex> LLM.supported_models(:openai)
      ["text-embedding-ada-002", "text-embedding-3-small", "text-embedding-3-large"]
  """
  @spec supported_models(provider()) :: [String.t()]
  def supported_models(provider) when is_atom(provider) do
    Map.get(@provider_models, provider, [])
  end

  @doc """
  Get information about all supported providers.

  ## Examples

      info = LLM.provider_info()
      Enum.each(info, fn {provider, details} ->
        IO.inspect({provider, details.models, details.env_vars})
      end)
  """
  @spec provider_info() :: map()
  def provider_info() do
    %{
      openai: %{
        models: @provider_models.openai,
        env_vars: ["OPENAI_API_KEY"],
        supports_dimensions: true,
        default_model: "text-embedding-ada-002"
      },
      google_vertex: %{
        models: @provider_models.google_vertex,
        env_vars: ["GOOGLE_API_KEY"],
        supports_dimensions: false,
        default_model: "textembedding-gecko"
      },
      google_gemini: %{
        models: @provider_models.google_gemini,
        env_vars: ["GOOGLE_API_KEY"],
        supports_dimensions: false,
        default_model: "embedding-001"
      },
      amazon_bedrock: %{
        models: @provider_models.amazon_bedrock,
        env_vars: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"],
        supports_dimensions: true,
        default_model: "amazon.titan-embed-text-v2"
      },
      voyageai: %{
        models: @provider_models.voyageai,
        env_vars: ["VOYAGEAI_API_KEY"],
        supports_dimensions: false,
        default_model: "voyage-2"
      },
      ollama: %{
        models: @provider_models.ollama,
        env_vars: [],
        supports_dimensions: false,
        default_model: "nomic-embed-text"
      }
    }
  end

  # Private functions

  defp validate_params(text, opts) do
    provider = Keyword.get(opts, :provider)

    cond do
      is_nil(provider) ->
        {:error, "Missing required option :provider"}

      provider not in [
        :amazon_bedrock,
        :google_vertex,
        :google_gemini,
        :ollama,
        :openai,
        :voyageai
      ] ->
        {:error, "Invalid provider: #{inspect(provider)}"}

      String.trim(text) == "" ->
        {:error, "Text cannot be empty"}

      true ->
        model = Keyword.get(opts, :model, get_default_model(provider))
        dimensions = Keyword.get(opts, :dimensions)
        region = Keyword.get(opts, :region)
        endpoint = Keyword.get(opts, :endpoint)

        params = %{
          text: text,
          provider: provider,
          model: model,
          dimensions: dimensions,
          region: region,
          endpoint: endpoint
        }

        {:ok, params}
    end
  end

  defp validate_batch_params(texts, opts) do
    cond do
      Enum.empty?(texts) ->
        {:error, "Texts list cannot be empty"}

      not Enum.all?(texts, &is_binary/1) ->
        {:error, "All texts must be strings"}

      true ->
        # Use first text for validation
        validate_params(List.first(texts), opts)
    end
  end

  defp get_default_model(provider) do
    case provider do
      :openai -> "text-embedding-ada-002"
      :google_vertex -> "textembedding-gecko"
      :google_gemini -> "embedding-001"
      :amazon_bedrock -> "amazon.titan-embed-text-v2"
      :voyageai -> "voyage-2"
      :ollama -> "nomic-embed-text"
      _ -> nil
    end
  end

  defp check_environment_variables(provider) do
    required_vars = get_required_env_vars(provider)

    missing_vars =
      required_vars
      |> Enum.reject(fn var -> System.get_env(var) != nil end)

    if Enum.empty?(missing_vars) do
      :ok
    else
      {:error, "Missing environment variables for #{provider}: #{Enum.join(missing_vars, ", ")}"}
    end
  end

  defp get_required_env_vars(provider) do
    case provider do
      :openai -> ["OPENAI_API_KEY"]
      :google_vertex -> ["GOOGLE_API_KEY"]
      :google_gemini -> ["GOOGLE_API_KEY"]
      :amazon_bedrock -> ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"]
      :voyageai -> ["VOYAGEAI_API_KEY"]
      :ollama -> []
      _ -> []
    end
  end

  defp build_embedding_query(params) do
    provider_str = Atom.to_string(params.provider) |> String.replace("_", "-")

    # Build the parameter list based on what's provided
    args = [
      "'#{escape_string(params.text)}'",
      "'#{provider_str}'",
      "'#{params.model}'"
    ]

    # Add optional parameters
    args =
      if params.dimensions do
        args ++ [Integer.to_string(params.dimensions)]
      else
        args ++ ["NULL"]
      end

    args =
      if params.region do
        args ++ ["'#{params.region}'"]
      else
        args ++ ["NULL"]
      end

    args =
      if params.endpoint do
        args ++ ["'#{params.endpoint}'"]
      else
        args ++ ["NULL"]
      end

    args_str = Enum.join(args, ", ")

    "CALL CREATE_EMBEDDING(#{args_str}) RETURN embedding;"
  end

  defp escape_string(str) do
    str
    |> String.replace("'", "\\'")
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
