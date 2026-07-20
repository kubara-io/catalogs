# kubara catalogs

This repository contains the catalog sources for **kubara**.

In kubara, a catalog is the reusable platform input that defines service metadata, Helm charts, Terraform modules, overlays, and other assets used to generate a platform setup.

## What is in this repository?

Today this repo contains the official catalogs that kubara uses as its default platform baseline:

- `bootstrap/` – the fixed bootstrap foundation, like Argo CD and bootstrap CRDs, used during the initial platform bring-up
- `general/` – the general reusable platform services that are meant to be selected and configured per cluster

These catalogs are versioned and meant to be packaged and distributed as OCI artifacts.

## What is this repo for?

This repo is the maintainable source for the official kubara catalogs.

That means:

- catalog manifests live here
- service definitions live here
- reusable platform stacks live here

kubara can consume these catalogs during schema generation, config initialization, platform generation, and bootstrap flows.

If you want to understand how catalogs fit into the bigger platform model, these docs are the best entry points:

- [Catalogs concept](https://docs.kubara.io/2_concepts/catalogs/)
- [Catalog templating](https://docs.kubara.io/2_concepts/catalog_templating/)
- [Components overview](https://docs.kubara.io/6_components/components_overview/)
- [Architecture overview](https://docs.kubara.io/7_architecture/architecture_overview/)

## Community and future direction

We want this repository to be a place for **community engagement** around reusable kubara platform stacks.

The current catalogs are only the starting point. We are open to growing this into a broader ecosystem with additional catalogs for different needs, for example:

- different infrastructure providers
- different opinionated platform stacks
- lighter or more enterprise-focused setups
- security, observability or developer-platform variants

That can include official catalogs, experimental catalogs, and community-driven catalogs over time.

If you want to propose a new stack, extend an existing catalog, improve service definitions, or contribute a new catalog direction entirely, contributions and discussion are welcome.

## Working with these catalogs

If you want to build your own catalog or adapt ideas from this repo:

1. Read [How to create a catalog](https://docs.kubara.io/4_building_your_platform/create_catalog/)
2. Read [Catalog distribution](https://docs.kubara.io/2_concepts/catalog_distribution/)
3. Use this repo as a real example of catalog structure and layout

## License

See [LICENSE](./LICENSE).
