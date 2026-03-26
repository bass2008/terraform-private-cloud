# Terraform — основная инфраструктура

Управляет инфраструктурой и сетью в Yandex Cloud.
State хранится в S3 бакете, созданном через [`bootstrap/`](bootstrap/README.md).

## Использование

**1. Задайте переменные окружения:**
```bash
export TF_VAR_yc_token="$(yc iam create-token)"
export TF_VAR_yc_cloud_id="$(yc config get cloud-id)"
export TF_VAR_yc_folder_id="$(yc config get folder-id)"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
```

> `AWS_ACCESS_KEY_ID` и `AWS_SECRET_ACCESS_KEY` берутся из `terraform/bootstrap/` (outputs `tf_state_access_key` / `tf_state_secret_key`).
> При пересоздании bootstrap-ресурсов ключи меняются — обновите их в своём окружении.

**2. Инициализируйте (только при первом клоне или смене провайдеров):**
```bash
terraform init -reconfigure
```

**3. Применяйте изменения:**
```bash
terraform apply
terraform output
```

## Удаление инфраструктуры

```bash
terraform destroy
```

> Бакет с terraform state не затрагивается — он управляется через `bootstrap/` и удаляется отдельно.
