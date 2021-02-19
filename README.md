# Ansible playbook: Bootstrap Wireguard on EC2

This playbook is intended to be called by a Terraform bootstrap script when provisioning an EC2 instance which will become a [Wireguard](https://www.wireguard.com/) VPN endpoint. It has been written in a manner to require no remote SSH into the instance to configure, as this requires punching a temporary hole in the firewall, which I didn't want to do.


##Installation

I've written the installation as terraform, but if you want to run this manually you can:

  1. [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html).
  2. Clone this repository to your EC2 instance
  3. `# ansible-galaxy collection install -r requirements.yml`
  4. `# ansible-galaxy install -r requirements.yml`
  5. `# ansible-playbook site.yml --extra-vars "@~/extra-vars.json"`


`~/extra-vars.json` contains the Terraform variables specifically for the [Ansible Wireguard role](https://github.com/githubixx/ansible-role-wireguard) into the Ansible playbook. Example:

    {
        "wireguard_endpoint": "x.x.x.x",
        "wireguard_preup": [
            "sysctl -w net.ipv4.ip_forward=1"
        ],
        "wireguard_postdown": [
            "iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
        ],
        "wireguard_persistent_keepalive": "30",
        "wireguard_save_config": "true",
        "wireguard_postup": [
            "iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
        ],
        "wireguard_predown": [
            "sysctl -w net.ipv4.ip_forward=0"
        ],
        "wireguard_address": "x.x.x.x/24",
        "wireguard_private_key": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=",
        "wireguard_unmanaged_peers": {
            "x.x.x.x": {
                "persistent_keepalive": "25",
                "public_key": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=",
                "endpoint": "x.x.x.x:51505",
                "allowed_ips": "x.x.x.x/32"
            }
        }
    }



## Acknowledgements
https://www.wireguard.com/

https://github.com/githubixx/

https://www.ifconfig.it/hugo/2020/04/aws-terraform-and-wireguard-part-one/


## Author

[Gav Main](https://github.com/gavmain), 2021.
