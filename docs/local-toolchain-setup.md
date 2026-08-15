# Local Toolchain Setup (Terraform + gcloud)

This project does not require cloud provisioning in Phase 0, but you should install and verify the core tools.

## 1) Install Terraform (Windows)

### Option A (recommended): winget

```powershell
winget install --id HashiCorp.Terraform -e
```

### Option B: manual install

1. Download Terraform for Windows (amd64) from HashiCorp releases.
2. Extract `terraform.exe`.
3. Put it in a folder such as `C:\Tools\Terraform`.
4. Add that folder to your `PATH`.

### Verify

```powershell
terraform --version
```

## 2) Install Google Cloud CLI (gcloud) on Windows

### Option A (recommended): winget

```powershell
winget install --id Google.CloudSDK -e
```

### Option B: manual install

1. Download the Google Cloud CLI installer for Windows.
2. Run the installer and enable PATH updates.
3. Reopen terminal.

### Verify

```powershell
gcloud --version
```

## 3) Optional first-time initialization (not required for Phase 0 completion)

```powershell
gcloud init
```

Phase 0 only requires tool availability checks, not real cloud authentication or resource provisioning.

