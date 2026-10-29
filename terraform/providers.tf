provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project             = "hipaa-cloud-reference"
      owner               = var.owner
      environment         = "lab"
      data_classification = "synthetic-phi"
      managed_by          = "terraform"
    }
  }
}
