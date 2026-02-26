all: clean create migrate run
clean:
	mix clean
create:
	mix deps.get
	mix ecto.create
migrate:
	mix ecto.migrate
run:
	iex -S mix phx.server
release:
	docker build -t discuss:latest -f docker/Dockerfile .
	docker run -it -e SECRET_KEY_BASE=$(mix phx.gen.secret) -p 80:4000 discuss:latest bash
docker-up:
	docker compose -f docker/docker-compose.yml up -d
docker-down:
	docker compose -f docker/docker-compose.yml down
