# Test Reports

Publish Playwright test report artifacts to GitHub Pages for client-visible test results.

## How it works

1. Tests run on the **live branch** and pass fully
2. `publish-report.sh` copies HTML reports, updates the index, pushes
3. GitHub Pages serves the reports at `https://<org>.github.io/test-reports/`

Only **100% passing runs on live** are published. Failed runs and non-live branches are skipped.

## Setup for a new client

### 1. Fork or create from this template

Each client org gets their own instance:

```bash
# Option A: Fork
gh repo fork ProxiBlue/test-reports --org ClientOrg --fork-name test-reports

# Option B: Create fresh and copy files
gh repo create ClientOrg/test-reports --private
# Then copy index.html, reports.json, publish-report.sh
```

### 2. Enable GitHub Pages

```bash
gh api repos/ClientOrg/test-reports/pages -X POST \
    -f "source[branch]=main" -f "source[path]=/"
```

### 3. Clone into the project

```bash
git clone git@github.com:ClientOrg/test-reports.git \
    /path/to/project/tests/test-reports
```

### 4. Publish after test runs

```bash
/path/to/tests/test-reports/publish-report.sh \
    site-name \
    /path/to/test-results/site/ \
    /path/to/project
```

## Report structure

```
test-reports/
├── index.html          # Browse all reports
├── reports.json        # Auto-updated index
├── publish-report.sh   # Publisher script
└── lcd/                # Site-specific reports
    └── 2026-04-27_0830/
        ├── index.html  # Run summary with links
        ├── admin/      # Playwright HTML report
        ├── hyva/       # Playwright HTML report
        └── default/    # Playwright HTML report
```

## Requirements

- GitHub Team/Enterprise plan (Pages on private repos)
- `jq` installed
- SSH access to the test-reports repo
