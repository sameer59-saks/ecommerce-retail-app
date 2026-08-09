# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

This is a fork of the AWS "retail-store-sample-app" microservices demo, adapted to showcase a **dual-branch GitOps workflow** on Amazon EKS. It contains five independent application services (`src/*`), Terraform infrastructure (`terraform/`), and Kubernetes/GitOps deployment config (`argocd/`, `src/*/chart`, `src/app/chart`).

**The two branches behave differently and this matters for almost every task:**

| | `main` | `gitops` (current branch) |
|---|---|---|
| Purpose | Simple/demo deployment | Production-style automated deployment |
| Images | Public ECR (fixed version tags) | Private ECR, built per-commit by CI |
| Deploy unit | Umbrella chart (`src/app/chart`) via one ArgoCD Application | Five individual ArgoCD Applications (`argocd/applications/*.yaml`), one per service |
| CI/CD | None (no `.github/workflows/`) | `.github/workflows/ci-cd.yml` builds/pushes changed services and auto-commits Helm chart updates |
| Chart values updates | Manual | Written by CI directly into `src/<service>/chart/values.yaml` (repository/tag) — don't hand-edit those fields on this branch, they get overwritten |

See `BRANCHING_STRATEGY.md` for the full rationale and `README.md` for the end-to-end deployment walkthrough.

## Architecture

Five decoupled services, each with its own language, build tool, Dockerfile, and Helm chart under `src/<service>/`:

- **`src/ui`** (Java/Spring Boot) — frontend; calls the other four services as backends.
- **`src/catalog`** (Go) — product catalog API, own MySQL-backed repository layer (`repository/`, `model/`, `controller/`, `api/`).
- **`src/cart`** (Java/Spring Boot) — shopping cart API, supports DynamoDB or in-memory backends.
- **`src/orders`** (Java/Spring Boot) — order management API, PostgreSQL-backed.
- **`src/checkout`** (Node/NestJS) — orchestrates checkout by calling `cart` and `orders` (see `src/checkout/src/clients/`); backed by Redis.

Each service directory is self-contained: `Dockerfile`, `docker-compose.yml` (local dev deps), `openapi.yml`, `chart/` (Helm chart with `values.yaml` holding the image repo/tag), and a `project.json` (Nx-style task definitions — `build`/`test`/`test:integration`/`lint`/`serve` — used as the canonical reference for each service's commands even though there's no root Nx workspace installed in this repo; run the underlying commands directly, see below).

**Deployment flow on `gitops` branch:**
1. Push to `src/<service>/**` on `main` or `gitops` → `ci-cd.yml` detects changed services via `dorny/paths-filter` and builds a matrix job per changed service.
2. Each changed service is built from its `Dockerfile`, tagged `<service>-<sha>` and `<service>-latest`, pushed to a single shared ECR repo (`ecommerce-store`).
3. CI rewrites `src/<service>/chart/values.yaml` (repository + tag) and commits/pushes that back to the branch.
4. ArgoCD (`argocd/applications/retail-store-<service>.yaml`, all under the `retail-store` AppProject) auto-syncs the changed chart into the `retail-store` namespace.

**Infrastructure (`terraform/`):** one flat root module — `main.tf` (VPC + EKS cluster, EKS Auto Mode with `general-purpose` node pool), `addons.tf` (NGINX ingress, cert-manager, monitoring add-ons), `argocd.tf` (installs ArgoCD via Helm and bootstraps `argocd/` Application/AppProject manifests), `security.tf`, `locals.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. `terraform/MONITORING.md` documents the optional `kube-prometheus-stack` monitoring add-on (`enable_monitoring=true` var, gated by `minimal-monitoring.tf`).

## Common commands

There is no root package manager/build tool installed — build/test/lint per-service using each service's own toolchain (mirrors the `project.json` target definitions):

### catalog (Go)
```sh
cd src/catalog
go build -o dist/main main.go   # build
go run main.go                  # serve locally
go test -v ./test/...           # integration tests
```

### cart / orders / ui (Java/Maven, Spring Boot)
```sh
cd src/<cart|orders|ui>
./mvnw --no-transfer-progress -DskipTests package   # build
./mvnw test -DexcludedGroups=integration            # unit tests
./mvnw test -Dgroups=integration                    # integration tests (cart needs AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY dummy env vars)
./mvnw checkstyle:checkstyle                        # lint
./mvnw spring-boot:run                              # serve locally
```
Run a single test class: `./mvnw test -Dtest=ClassName`.

### checkout (Node/NestJS, yarn)
```sh
cd src/checkout
yarn install
yarn build            # nest build
yarn serve:dev        # nest start --watch
yarn lint / yarn lint:fix
yarn test:cov         # jest with coverage
yarn test:integration # jest --config ./test/jest-e2e.json
```

### Local dependency stack
Each service has its own `docker-compose.yml` for local backing services (DB, queue, etc.); `ui` additionally exposes Nx-style `compose:up` / `compose:down` (`docker compose up --build --detach --wait` / `docker compose down`).

### Infrastructure
```sh
cd terraform
terraform init
terraform apply --auto-approve                 # provisions VPC/EKS/ArgoCD/ingress/cert-manager
terraform apply -var="enable_monitoring=true"   # optional Prometheus/Grafana stack
terraform destroy --auto-approve                # teardown (note: ECR repos must be deleted manually)
```
```sh
aws eks update-kubeconfig --name retail-store --region <region>
kubectl get pods -n retail-store
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Working with this repo

- Know which branch you're on before touching chart values or ArgoCD manifests — `main` uses `src/app/chart` (umbrella), `gitops` uses per-service charts driven by CI.
- On `gitops`, `src/<service>/chart/values.yaml` repository/tag fields are CI-managed; changes to them will be overwritten by the next `ci-cd.yml` run on that service.
- `argocd/applications/*.yaml` and `argocd/projects/retail-store-project.yaml` point at `repoURL: https://github.com/sameer59-saks/ecommerce-retail-app.git` with `targetRevision: gitops` — update these if the fork/remote changes.
- `terraform/*.tfstate*` files are committed in this working copy; treat them as live state, not disposable fixtures.
