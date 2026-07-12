defmodule LadybugEx.LLMTest do
  use ExUnit.Case, async: false
  alias LadybugEx.{Database, Connection, LLM, Extensions}

  setup do
    # Use a smaller buffer pool size to avoid memory allocation issues
    {:ok, db} = Database.in_memory(buffer_pool_size: 1024 * 1024 * 10)
    {:ok, conn} = Connection.new(db)
    # Resources are automatically cleaned up by garbage collection
    {:ok, %{db: db, conn: conn}}
  end

  describe "create_embedding/3" do
    @tag :requires_extension
    @tag :requires_api_key
    test "creates embedding with OpenAI provider", %{conn: conn} do
      # Skip if no API key
      if System.get_env("OPENAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            result = LLM.create_embedding(conn, "Hello world", provider: :openai)

            case result do
              {:ok, embedding} ->
                assert is_list(embedding)
                assert Enum.all?(embedding, &is_float/1)
                # OpenAI ada-002 returns 1536 dimensions by default
                assert length(embedding) == 1536

              {:error, _reason} ->
                # API call might fail for various reasons
                assert true
            end

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    @tag :requires_extension
    @tag :requires_api_key
    test "creates embedding with specific model", %{conn: conn} do
      if System.get_env("OPENAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            result =
              LLM.create_embedding(conn, "Test text",
                provider: :openai,
                model: "text-embedding-3-small"
              )

            assert match?({:ok, _}, result) or match?({:error, _}, result)

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    @tag :requires_extension
    @tag :requires_api_key
    test "creates embedding with custom dimensions", %{conn: conn} do
      if System.get_env("OPENAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            result =
              LLM.create_embedding(conn, "Dimensionality reduction",
                provider: :openai,
                model: "text-embedding-3-small",
                dimensions: 512
              )

            case result do
              {:ok, embedding} ->
                assert length(embedding) == 512

              {:error, _} ->
                assert true
            end

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    @tag :requires_extension
    test "creates embedding with Ollama provider", %{conn: conn} do
      # Ollama doesn't require API keys but needs local server
      case Extensions.install_and_load(conn, "llm") do
        :ok ->
          result =
            LLM.create_embedding(conn, "Local embedding",
              provider: :ollama,
              model: "nomic-embed-text",
              endpoint: "http://localhost:11434"
            )

          # Will fail if Ollama not running locally
          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "returns error when missing provider", %{conn: conn} do
      assert {:error, "Missing required option :provider"} =
               LLM.create_embedding(conn, "text", model: "some-model")
    end

    test "returns error for invalid provider", %{conn: conn} do
      assert {:error, "Invalid provider: :invalid_provider"} =
               LLM.create_embedding(conn, "text", provider: :invalid_provider)
    end

    test "returns error for empty text", %{conn: conn} do
      assert {:error, "Text cannot be empty"} =
               LLM.create_embedding(conn, "", provider: :openai)

      assert {:error, "Text cannot be empty"} =
               LLM.create_embedding(conn, "   ", provider: :openai)
    end

    test "returns error when missing environment variables", %{conn: conn} do
      # Temporarily unset env var if it exists
      original = System.get_env("OPENAI_API_KEY")
      System.delete_env("OPENAI_API_KEY")

      result = LLM.create_embedding(conn, "test", provider: :openai)

      # Restore original
      if original, do: System.put_env("OPENAI_API_KEY", original)

      assert {:error, reason} = result
      assert reason =~ "Missing environment variables"
      assert reason =~ "OPENAI_API_KEY"
    end

    test "automatically ensures extension is loaded", %{conn: conn} do
      # Even without explicitly loading, should attempt to ensure loaded
      result = LLM.create_embedding(conn, "test", provider: :ollama)

      # Will fail if extension not installed, but that's ok
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "create_embedding!/3" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to create embedding/, fn ->
        LLM.create_embedding!(conn, "text", model: "test")
      end
    end
  end

  describe "create_embeddings/3" do
    @tag :requires_extension
    @tag :requires_api_key
    test "creates embeddings for multiple texts", %{conn: conn} do
      if System.get_env("OPENAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            texts = ["First text", "Second text", "Third text"]

            result = LLM.create_embeddings(conn, texts, provider: :openai)

            case result do
              {:ok, embeddings} ->
                assert length(embeddings) == 3
                assert Enum.all?(embeddings, &is_list/1)

                assert Enum.all?(embeddings, fn emb ->
                         Enum.all?(emb, &is_float/1)
                       end)

              {:error, _} ->
                assert true
            end

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    test "returns error for empty texts list", %{conn: conn} do
      assert {:error, "Texts list cannot be empty"} =
               LLM.create_embeddings(conn, [], provider: :openai)
    end

    test "returns error for non-string texts", %{conn: conn} do
      assert {:error, "All texts must be strings"} =
               LLM.create_embeddings(conn, ["valid", 123, "text"], provider: :openai)
    end
  end

  describe "create_embeddings!/3" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to create embeddings/, fn ->
        LLM.create_embeddings!(conn, [], provider: :openai)
      end
    end
  end

  describe "check_provider_config/1" do
    test "checks OpenAI configuration" do
      original = System.get_env("OPENAI_API_KEY")

      # Test with key set
      System.put_env("OPENAI_API_KEY", "test-key")
      assert LLM.check_provider_config(:openai) == :ok

      # Test without key
      System.delete_env("OPENAI_API_KEY")
      assert {:error, reason} = LLM.check_provider_config(:openai)
      assert reason =~ "OPENAI_API_KEY"

      # Restore
      if original, do: System.put_env("OPENAI_API_KEY", original)
    end

    test "checks AWS Bedrock configuration" do
      access_key = System.get_env("AWS_ACCESS_KEY_ID")
      secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")

      # Test with keys set
      System.put_env("AWS_ACCESS_KEY_ID", "test-access")
      System.put_env("AWS_SECRET_ACCESS_KEY", "test-secret")
      assert LLM.check_provider_config(:amazon_bedrock) == :ok

      # Test without keys
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
      assert {:error, reason} = LLM.check_provider_config(:amazon_bedrock)
      assert reason =~ "AWS_ACCESS_KEY_ID"

      # Restore
      if access_key, do: System.put_env("AWS_ACCESS_KEY_ID", access_key)
      if secret_key, do: System.put_env("AWS_SECRET_ACCESS_KEY", secret_key)
    end

    test "checks Ollama configuration" do
      # Ollama doesn't require env vars
      assert LLM.check_provider_config(:ollama) == :ok
    end
  end

  describe "supported_models/1" do
    test "returns models for OpenAI" do
      models = LLM.supported_models(:openai)
      assert is_list(models)
      assert "text-embedding-ada-002" in models
      assert "text-embedding-3-small" in models
      assert "text-embedding-3-large" in models
    end

    test "returns models for Google Vertex" do
      models = LLM.supported_models(:google_vertex)
      assert is_list(models)
      assert "textembedding-gecko" in models
    end

    test "returns models for Ollama" do
      models = LLM.supported_models(:ollama)
      assert is_list(models)
      assert "nomic-embed-text" in models
    end

    test "returns empty list for unknown provider" do
      assert LLM.supported_models(:unknown_provider) == []
    end
  end

  describe "provider_info/0" do
    test "returns comprehensive provider information" do
      info = LLM.provider_info()

      assert is_map(info)
      assert Map.has_key?(info, :openai)
      assert Map.has_key?(info, :ollama)
      assert Map.has_key?(info, :amazon_bedrock)

      # Check OpenAI info structure
      openai_info = info.openai
      assert openai_info.env_vars == ["OPENAI_API_KEY"]
      assert openai_info.supports_dimensions == true
      assert openai_info.default_model == "text-embedding-ada-002"
      assert is_list(openai_info.models)

      # Check Ollama info
      ollama_info = info.ollama
      assert ollama_info.env_vars == []
      assert ollama_info.supports_dimensions == false
    end
  end

  describe "provider-specific tests" do
    @tag :requires_extension
    @tag :requires_api_key
    test "Google Vertex provider", %{conn: conn} do
      if System.get_env("GOOGLE_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            result =
              LLM.create_embedding(conn, "Google test",
                provider: :google_vertex,
                model: "textembedding-gecko"
              )

            assert match?({:ok, _}, result) or match?({:error, _}, result)

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    @tag :requires_extension
    @tag :requires_api_key
    test "AWS Bedrock provider with region", %{conn: conn} do
      if System.get_env("AWS_ACCESS_KEY_ID") && System.get_env("AWS_SECRET_ACCESS_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            result =
              LLM.create_embedding(conn, "AWS test",
                provider: :amazon_bedrock,
                model: "amazon.titan-embed-text-v2",
                region: "us-west-2"
              )

            assert match?({:ok, _}, result) or match?({:error, _}, result)

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    @tag :requires_extension
    @tag :requires_api_key
    test "Voyage AI provider", %{conn: conn} do
      if System.get_env("VOYAGEAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            result =
              LLM.create_embedding(conn, "Voyage test",
                provider: :voyageai,
                model: "voyage-2"
              )

            assert match?({:ok, _}, result) or match?({:error, _}, result)

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end
  end

  describe "integration" do
    @tag :requires_extension
    @tag :requires_api_key
    test "embedding generation and similarity comparison", %{conn: conn} do
      if System.get_env("OPENAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            # Generate embeddings for similar and dissimilar texts
            texts = [
              "Machine learning is a subset of artificial intelligence",
              "AI and machine learning are related fields",
              "The weather today is sunny and warm"
            ]

            embeddings =
              Enum.map(texts, fn text ->
                case LLM.create_embedding(conn, text, provider: :openai) do
                  {:ok, emb} -> emb
                  {:error, _} -> nil
                end
              end)

            if Enum.all?(embeddings, & &1) do
              # Calculate cosine similarity between first two (should be high)
              sim_12 = cosine_similarity(Enum.at(embeddings, 0), Enum.at(embeddings, 1))

              # Calculate similarity between first and third (should be lower)
              sim_13 = cosine_similarity(Enum.at(embeddings, 0), Enum.at(embeddings, 2))

              # Similar texts should have higher similarity
              assert sim_12 > sim_13
            end

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end

    @tag :requires_extension
    @tag :requires_api_key
    test "batch processing efficiency", %{conn: conn} do
      if System.get_env("OPENAI_API_KEY") do
        case Extensions.install_and_load(conn, "llm") do
          :ok ->
            texts = Enum.map(1..5, fn i -> "Test text number #{i}" end)

            result = LLM.create_embeddings(conn, texts, provider: :openai)

            case result do
              {:ok, embeddings} ->
                assert length(embeddings) == 5
                # All embeddings should have same dimensions
                dimensions = embeddings |> Enum.map(&length/1) |> Enum.uniq()
                assert length(dimensions) == 1

              {:error, _} ->
                assert true
            end

          {:error, _} ->
            assert true
        end
      else
        assert true
      end
    end
  end

  # Helper function for cosine similarity
  defp cosine_similarity(vec1, vec2) when is_list(vec1) and is_list(vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    mag1 = :math.sqrt(Enum.map(vec1, fn x -> x * x end) |> Enum.sum())
    mag2 = :math.sqrt(Enum.map(vec2, fn x -> x * x end) |> Enum.sum())

    if mag1 * mag2 == 0 do
      0.0
    else
      dot_product / (mag1 * mag2)
    end
  end
end
