// module "pg-admin-prod" {
//   source       = "./modules/pg-admin"
//   env          = "prod"
//   cidr_block   = "10.0.0.0/16"
//   db_name      = "prod_db"
//   db_username  = "db_admin"
//   route53_zone = "rogozin.de"
//   project      = "rogozin.de"
//   hostname     = "pg-admin"
//   ssm_pg_admin_pass_arn = "arn:aws:ssm:eu-central-1:198464718186:parameter/pg_admin_pass"

// }

module "pg-admin-stage" {
  source       = "./modules/pg-admin"
  env          = "stage"
  cidr_block   = "10.1.0.0/16"
  db_name      = "prod_db"
  db_username  = "db_admin"
  route53_zone = "rogozin.de"
  project      = "stage-rogozin.de"
  hostname     = "pg-admin-stage"
}
