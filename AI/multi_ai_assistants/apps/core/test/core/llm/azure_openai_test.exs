defmodule Core.LLM.AzureOpenAITest do
  use ExUnit.Case, async: false

  alias Core.LLM.AzureOpenAI

  setup do
    original_endpoint = Application.get_env(:core, :azure_openai_endpoint)
    original_api_key = Application.get_env(:core, :azure_openai_api_key)

    on_exit(fn ->
      restore_env(:azure_openai_endpoint, original_endpoint)
      restore_env(:azure_openai_api_key, original_api_key)
    end)

    :ok
  end

  test "chat_completion returns a configuration error when endpoint is missing" do
    Application.put_env(:core, :azure_openai_endpoint, nil)
    Application.put_env(:core, :azure_openai_api_key, "test-key")

    assert {:error, {:missing_config, :azure_openai_endpoint}} =
             AzureOpenAI.chat_completion([%{role: "user", content: "hello"}])
  end

  test "stream_chat_completion returns a configuration error when API key is missing" do
    Application.put_env(:core, :azure_openai_endpoint, "https://example.openai.azure.com")
    Application.put_env(:core, :azure_openai_api_key, "")

    assert {:error, {:missing_config, :azure_openai_api_key}} =
             AzureOpenAI.stream_chat_completion([%{role: "user", content: "hello"}], [], fn _ ->
               :ok
             end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:core, key)
  defp restore_env(key, value), do: Application.put_env(:core, key, value)
end
