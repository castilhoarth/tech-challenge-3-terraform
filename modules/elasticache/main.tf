resource "aws_elasticache_subnet_group" "main" {
  name       = "toggle-master-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "toggle-master-redis_sg" {
  name   = "toggle-master-redis-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "toggle-master-redis-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.toggle-master-redis_sg.id]
}
