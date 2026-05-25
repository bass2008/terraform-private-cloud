# Bootstrap — создание S3 backend для Terraform state

Выполняется **один раз** перед первым запуском основного terraform.
Создаёт сервисный аккаунт, статический ключ доступа и S3-бакет для хранения terraform state.

## Первый запуск

**1. Задайте переменные окружения:**
```bash
export TF_VAR_yc_token="$(yc iam create-token)"
export TF_VAR_yc_cloud_id="$(yc config get cloud-id)"
export TF_VAR_yc_folder_id="$(yc config get folder-id)"
```

**2. Инициализируйте и создайте ресурсы:**
```bash
cd terraform/bootstrap/
terraform init
terraform apply
```

**3. Сохраните ключи доступа:**
```bash
terraform output -raw tf_state_access_key
terraform output -raw tf_state_secret_key
```

Запишите значения — они понадобятся при каждом запуске основного terraform.

---

## Удаление

Bootstrap-ресурсы удаляются вручную **после** удаления основной инфраструктуры:

```bash
# 1. Очистить содержимое бакета (включая все версии объектов)
# 2. Удалить бакет:
yc storage bucket delete --name private-cloud-tfstate-hjb4rfs
# 3. Удалить ресурсы terraform:
terraform destroy
```

> `terraform destroy` в основном (`terraform/`) бакет не трогает — он управляется только отсюда.
