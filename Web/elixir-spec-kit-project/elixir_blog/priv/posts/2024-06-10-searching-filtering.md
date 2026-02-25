---
title: "고급 검색 및 필터링 구현"
author: "강민지"
tags: ["database", "search", "architecture"]
thumbnail: "/images/thumbnails/searching-filtering.jpg"
summary: "Elasticsearch 또는 전문 검색 기능을 이용한 검색 구현을 배웁니다."
published_at: 2024-06-10T09:20:00Z
is_popular: false
---

효율적인 검색은 사용자 경험을 크게 향상시킵니다. 다양한 검색 기법을 알아봅시다.

## 데이터베이스 전문 검색

```elixir
# PostgreSQL 전문 검색
defmodule PostRepository do
  def search(query) do
    from(p in Post,
      where: fragment(
        "to_tsvector('korean', ?) @@ plainto_tsquery('korean', ?)",
        p.content,
        ^query
      )
    )
    |> Repo.all()
  end

  def search_with_ranking(query) do
    from(p in Post,
      select: {p, fragment(
        "ts_rank(to_tsvector('korean', ?), plainto_tsquery('korean', ?))",
        p.content,
        ^query
      )},
      where: fragment(
        "to_tsvector('korean', ?) @@ plainto_tsquery('korean', ?)",
        p.content,
        ^query
      ),
      order_by: [desc: fragment(
        "ts_rank(to_tsvector('korean', ?), plainto_tsquery('korean', ?))",
        p.content,
        ^query
      )]
    )
    |> Repo.all()
    |> Enum.map(fn {post, _rank} -> post end)
  end
end
```

## Elasticsearch 통합

```elixir
# lib/myapp/search/elasticsearch_client.ex
defmodule Myapp.Search.ElasticsearchClient do
  def search(index, query) do
    body = %{
      query: %{
        multi_match: %{
          query: query,
          fields: ["title^2", "content", "tags"],
          fuzziness: "AUTO"
        }
      }
    }

    case Elasticsearch.post(client(), "/#{index}/_search", body) do
      {:ok, %{"hits" => %{"hits" => results}}} ->
        Enum.map(results, & &1["_source"])
      {:error, reason} ->
        {:error, reason}
    end
  end

  def index_document(index, id, document) do
    Elasticsearch.put(client(), "/#{index}/_doc/#{id}", document)
  end

  def delete_document(index, id) do
    Elasticsearch.delete(client(), "/#{index}/_doc/#{id}")
  end

  defp client do
    Elasticsearch.Client.new([
      url: "http://localhost:9200"
    ])
  end
end

# 사용
Myapp.Search.ElasticsearchClient.search("posts", "elixir")
```

## 필터링 시스템

```elixir
defmodule FilterEngine do
  def apply_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, acc ->
      apply_filter(acc, key, value)
    end)
  end

  defp apply_filter(query, :status, status) do
    from(p in query, where: p.status == ^status)
  end

  defp apply_filter(query, :category, category) do
    from(p in query, where: p.category == ^category)
  end

  defp apply_filter(query, :date_range, %{from: from_date, to: to_date}) do
    from(p in query,
      where: p.created_at >= ^from_date and p.created_at <= ^to_date
    )
  end

  defp apply_filter(query, :author, author_id) do
    from(p in query, where: p.author_id == ^author_id)
  end

  defp apply_filter(query, :tags, tags) when is_list(tags) do
    from(p in query,
      join: t in assoc(p, :tags),
      where: t.name in ^tags,
      distinct: p.id
    )
  end

  defp apply_filter(query, :price_range, %{min: min_price, max: max_price}) do
    from(p in query,
      where: p.price >= ^min_price and p.price <= ^max_price
    )
  end

  defp apply_filter(query, _key, _value) do
    query
  end
end

# 컨트롤러에서 사용
def search(conn, params) do
  filters = %{
    status: params["status"],
    category: params["category"],
    date_range: parse_date_range(params),
    tags: String.split(params["tags"] || "", ",")
  }
  |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
  |> Enum.into(%{})

  results = Post
    |> FilterEngine.apply_filters(filters)
    |> Repo.all()

  json(conn, results)
end
```

## 정렬 및 페이지네이션

```elixir
defmodule PaginationHelper do
  def paginate(query, page \\ 1, per_page \\ 10) do
    offset = (page - 1) * per_page

    total = Repo.aggregate(query, :count)
    pages = ceil(total / per_page)

    results = query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      data: results,
      pagination: %{
        page: page,
        per_page: per_page,
        total: total,
        pages: pages,
        has_prev: page > 1,
        has_next: page < pages
      }
    }
  end

  def sort(query, sort_field, direction \\ :asc) do
    from(q in query, order_by: [{^direction, ^sort_field}])
  end
end

# 사용
Post
|> PaginationHelper.sort(:created_at, :desc)
|> PaginationHelper.paginate(1, 20)
```

## 동적 쿼리 빌더

```elixir
defmodule DynamicQueryBuilder do
  def build(base_query, criteria) do
    Enum.reduce(criteria, base_query, fn {field, value}, query ->
      build_condition(query, field, value)
    end)
  end

  defp build_condition(query, :title, value) do
    from(q in query, where: like(q.title, ^"%#{value}%"))
  end

  defp build_condition(query, :status, value) do
    from(q in query, where: q.status == ^value)
  end

  defp build_condition(query, :min_price, value) do
    from(q in query, where: q.price >= ^value)
  end

  defp build_condition(query, :max_price, value) do
    from(q in query, where: q.price <= ^value)
  end

  defp build_condition(query, _field, _value) do
    query
  end
end
```

## 결론

강력한 검색 기능은 사용자가 원하는 데이터를 빠르게 찾을 수 있게 합니다. 데이터베이스 전문 검색부터 Elasticsearch까지 다양한 옵션을 상황에 맞게 선택할 수 있습니다.