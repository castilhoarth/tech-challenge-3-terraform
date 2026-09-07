# 1. Gera uma senha aleatória forte para cada banco de dados
resource "random_password" "master_password" {
    for_each = var.instances

    length           = 16
    special          = true
    override_special = "-_" # Sem @, /, " ou espaço
}

# 2. Cria a Secret no Secrest Manager
resource "aws_secretsmanager_secret" "db_secret" {
    for_each = var.instances

    name = "tech-challenge/rds-${each.key}"

    # Crucial para o Academy:
    # Define o tempo de retenção para 0 dias, permitindo que a Secret seja
    # destruída imediatamente no 'Terraform destroy' sem travar novas execuções.
    recovery_window_in_days = 0
}

# 3. Guarda as credenciais (usuário e senha, engine e porta) no Secret Manager
resource "aws_secretsmanager_secret_version" "db_secret_version" {
    for_each = var.instances

    secret_id = aws_secretsmanager_secret.db_secret[each.key].id
    secret_string = jsonencode({
        username = lookup(each.value, "username", "dbadmin")
        password = random_password.master_password[each.key].result
        engine   = "postgres"
        port     = 5432
        db_name  = each.value.databases[0]
    })
}

# 4. Cria o Subnet Group e Security Group do RDS
resource "aws_db_subnet_group" "main" {
    name = "toggle-master-db-subnet-group"
    subnet_ids = var.subnet_ids
}

resource "aws_security_group" "toggle-master-rds_sg" {
    name = "toggle-master-rds-sg"
    vpc_id = var.vpc_id

    ingress {
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        security_groups = [var.eks_security_group_id]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

# 5. Cria as instâncias RDS PostgreSQL consumindo a senha gerada
resource "aws_db_instance" "postgres" {
    for_each = var.instances

    identifier        = "rds-${each.key}"
    allocated_storage = 20
    engine            = "postgres"
    engine_version    = "15"
    instance_class    = "db.t3.micro"
    db_name           = each.value.databases[0]
    username          = each.value.username
    password          = random_password.master_password[each.key].result

    db_subnet_group_name   = aws_db_subnet_group.main.name
    vpc_security_group_ids = [aws_security_group.toggle-master-rds_sg.id]
    skip_final_snapshot    = true
}
