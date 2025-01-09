resource "aiven_pg" "postgres" {
   project                 = var.project_name
   service_name            = "postgres-aws-us"
   cloud_name              = "aws-us-west-2"
   plan                    = "hobbyist"
   maintenance_window_dow  = "monday"
   maintenance_window_time = "10:00:00"
}