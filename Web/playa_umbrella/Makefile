dev: clean create migrate seed run

prod: pack ship launch

clean:
	@echo ------------------------------------------
	@echo Cleaning
	@echo ------------------------------------------
	mix clean

docker_down:
	@echo ------------------------------------------
	@echo Docker down
	@echo ------------------------------------------
	@echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	@echo This is very dangerous Actions
	@echo !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	docker compose down --volumes --remove-orphans
	sudo rm -rf /var/docker/postgresql

docker_up:
	@echo ------------------------------------------
	@echo Docker down
	@echo ------------------------------------------
	docker compose up --build --detach
	sleep 5

create:
	@echo ------------------------------------------
	@echo Creating
	@echo ------------------------------------------
	mix deps.get
	mix ecto.create

migrate:
	@echo ------------------------------------------
	@echo Migrating
	@echo ------------------------------------------
	mix ecto.migrate --repo Playa.Repo
	mix ecto.migrate --repo Productivity.Repo

seed:
	@echo ------------------------------------------
	@echo Seeting
	@echo ------------------------------------------
	mix run apps/playa/priv/repo/seeds.exs
	mix run apps/productivity/priv/repo/seeds.exs

format:
	@echo ------------------------------------------
	@echo Code formatting
	@echo ------------------------------------------
	mix format

test:
	@echo ------------------------------------------
	@echo Code Testing
	@echo ------------------------------------------
	mix test --cover

run:
	@echo ------------------------------------------
	@echo Running
	@echo ------------------------------------------
	iex -S mix phx.server

pack:
	@echo ------------------------------------------
	@echo Packing
	@echo ------------------------------------------
	mix deps.get --only prod
	MIX_ENV=prod mix compile
	MIX_ENV=prod mix assets.deploy
	cd ./apps/playa_web/; mix phx.gen.release
	MIX_ENV=prod mix release

ship:
	@echo ------------------------------------------
	@echo Shipping
	@echo ------------------------------------------
	docker build --tag playa_umbrella:latest .

launch:
	@echo ------------------------------------------
	@echo Launching
	@echo ------------------------------------------
	docker run                                 \
		--name playa_umbrella                    \
		--network $(DOCKER_NETWORK)              \
    --env DATABASE_URL=$(DATABASE_URL)       \
    --env SECRET_KEY_BASE=$(SECRET_KEY_BASE) \
    --publish 4000:4000                      \
    --detach                                 \
    playa_umbrella start
