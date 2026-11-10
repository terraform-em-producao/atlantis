# O Atlantis guarda locks, planos e clones no disco (BoltDB em ATLANTIS_DATA_DIR).
# No Fargate o disco some a cada deploy; sem EFS, um restart perde os locks
# e dois PRs podem aplicar no mesmo state.
resource "aws_efs_file_system" "atlantis" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  tags = { Name = "atlantis" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_efs_mount_target" "atlantis" {
  count = length(aws_subnet.publica)

  file_system_id  = aws_efs_file_system.atlantis.id
  subnet_id       = aws_subnet.publica[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# A imagem roda como atlantis (uid 100, gid 1000).
resource "aws_efs_access_point" "atlantis" {
  file_system_id = aws_efs_file_system.atlantis.id

  posix_user {
    uid = 100
    gid = 1000
  }

  root_directory {
    path = "/atlantis"

    creation_info {
      owner_uid   = 100
      owner_gid   = 1000
      permissions = "0750"
    }
  }
}
