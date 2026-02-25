---
title: "Elixir에서 머신러닝 모델 통합"
author: "정수진"
tags: ["machine-learning", "ai", "elixir"]
thumbnail: "/images/thumbnails/ml-integration.jpg"
summary: "Elixir 애플리케이션에 머신러닝 모델을 통합하는 방법을 배웁니다."
published_at: 2024-08-01T10:00:00Z
is_popular: false
---

머신러닝은 현대 애플리케이션의 중요한 부분입니다. Elixir와 머신러닝 모델을 통합해봅시다.

## TensorFlow Lite 통합

```elixir
# mix.exs
defp deps do
  [
    {:tflite, "~> 0.1"}
  ]
end

# lib/myapp/ml/image_classifier.ex
defmodule Myapp.ML.ImageClassifier do
  def load_model do
    model_path = "priv/models/mobilenet_v2.tflite"
    TFLite.Interpreter.new(model_path)
  end

  def classify_image(image_path) do
    interpreter = load_model()

    image = Image.load!(image_path)
    input = preprocess_image(image)

    {status, results} = TFLite.Interpreter.predict(interpreter, [input])

    case status do
      :ok -> {:ok, postprocess_results(results)}
      :error -> {:error, "Classification failed"}
    end
  end

  defp preprocess_image(image) do
    image
    |> Image.resize(224, 224)
    |> Image.normalize()
    |> Image.to_tensor()
  end

  defp postprocess_results(results) do
    results
    |> Enum.sort_by(fn {_label, score} -> score end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {label, score} ->
      %{label: label, confidence: Float.round(score, 4)}
    end)
  end
end
```

## Python 모델 서빙

```elixir
# lib/myapp/ml/python_model_server.ex
defmodule Myapp.ML.PythonModelServer do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    port = Port.open({:spawn, "python priv/models/model_server.py"}, [:binary])
    {:ok, %{port: port}}
  end

  def predict(features) do
    GenServer.call(__MODULE__, {:predict, features}, 10000)
  end

  def handle_call({:predict, features}, _from, %{port: port} = state) do
    request = Jason.encode!(%{features: features})

    Port.command(port, request <> "\n")

    response = receive do
      {^port, {:data, data}} ->
        Jason.decode!(data)
    end

    {:reply, response, state}
  end

  def terminate(_reason, %{port: port}) do
    Port.close(port)
  end
end

# Python 모델 서버
# priv/models/model_server.py
import json
import sys
import pickle

# 모델 로드
with open('model.pkl', 'rb') as f:
    model = pickle.load(f)

for line in sys.stdin:
    request = json.loads(line)
    features = request['features']
    prediction = model.predict([features])
    response = {'prediction': float(prediction[0])}
    print(json.dumps(response))
    sys.stdout.flush()
```

## 추천 시스템

```elixir
defmodule Myapp.ML.RecommendationEngine do
  def get_recommendations(user_id, limit \\ 5) do
    user_vector = get_user_vector(user_id)
    all_item_vectors = get_all_item_vectors()

    similarities = calculate_similarities(user_vector, all_item_vectors)

    similarities
    |> Enum.sort_by(fn {_item_id, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {item_id, score} ->
      %{item_id: item_id, score: Float.round(score, 4)}
    end)
  end

  defp get_user_vector(user_id) do
    # 사용자 벡터 계산 또는 캐시에서 조회
    Cachex.get!(:ml_cache, "user_vector:#{user_id}")
  end

  defp get_all_item_vectors do
    # 모든 아이템 벡터 조회
    Repo.all(from i in Item, select: {i.id, i.vector})
  end

  defp calculate_similarities(user_vector, item_vectors) do
    Enum.map(item_vectors, fn {item_id, item_vector} ->
      similarity = cosine_similarity(user_vector, item_vector)
      {item_id, similarity}
    end)
  end

  defp cosine_similarity(vec1, vec2) do
    dot_product = Enum.zip(vec1, vec2)
      |> Enum.map(fn {a, b} -> a * b end)
      |> Enum.sum()

    magnitude1 = :math.sqrt(Enum.sum(Enum.map(vec1, &(&1 * &1))))
    magnitude2 = :math.sqrt(Enum.sum(Enum.map(vec2, &(&1 * &1))))

    case magnitude1 * magnitude2 do
      0 -> 0
      product -> dot_product / product
    end
  end
end
```

## 스팸 탐지

```elixir
defmodule Myapp.ML.SpamDetector do
  def is_spam?(text) do
    features = extract_features(text)

    case predict_spam(features) do
      {_status, probability} -> probability > 0.5
    end
  end

  defp extract_features(text) do
    %{
      length: String.length(text),
      uppercase_ratio: count_uppercase(text) / String.length(text),
      link_count: count_links(text),
      exclamation_count: String.count(text, "!"),
      has_suspicious_words: contains_suspicious_words?(text)
    }
  end

  defp predict_spam(features) do
    Myapp.ML.PythonModelServer.predict([
      features.length,
      features.uppercase_ratio,
      features.link_count,
      features.exclamation_count,
      if(features.has_suspicious_words, do: 1, else: 0)
    ])
  end

  defp count_uppercase(text) do
    text
    |> String.graphemes()
    |> Enum.count(&String.match?(&1, ~r/[A-Z]/))
  end

  defp count_links(text) do
    Regex.scan(~r/https?:\/\//, text)
    |> length()
  end

  defp contains_suspicious_words?(text) do
    suspicious_words = ["click here", "limited offer", "act now"]
    Enum.any?(suspicious_words, fn word -> String.contains?(text, word) end)
  end
end
```

## 결론

Elixir와 머신러닝 모델의 통합으로 지능형 애플리케이션을 만들 수 있습니다. TensorFlow, 파이썬 모델, 벡터 유사도 계산 등을 활용하여 다양한 ML 기능을 구현할 수 있습니다.