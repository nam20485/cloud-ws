# variables.tf

variable "robot_user" {
  type        = string
  description = "Hetzner Robot API username."
  sensitive   = true
}

variable "robot_pass" {
  type        = string
  description = "Hetzner Robot API password."
  sensitive   = true
}

variable "server_model" {
  type        = string
  description = "The model name of the dedicated server to order (e.g., 'AX102')."
  default     = "AX102" # A powerful server with NVMe options
}

variable "ssh_key_fingerprints" {
  type        = list(string)
  description = "A list of SSH key MD5 fingerprints to authorize for root login."
  default     = ["MD5:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"] # <-- IMPORTANT: REPLACE THIS
}
