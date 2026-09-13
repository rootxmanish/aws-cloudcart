# CloudCart Security Groups

## public-lb-sg
Inbound:
- TCP 80 from 0.0.0.0/0
- TCP 443 from 0.0.0.0/0

Outbound:
- TCP 80 to webserver-sg

## webserver-sg
Inbound:
- TCP 80 from public-lb-sg
- TCP 22 from bastion-sg

Outbound:
- TCP 8000 to private-lb-sg
- TCP 443 to 0.0.0.0/0 if updates are needed

## private-lb-sg
Inbound:
- TCP 8000 from webserver-sg

Outbound:
- TCP 8000 to appserver-sg

## appserver-sg
Inbound:
- TCP 8000 from private-lb-sg
- TCP 22 from bastion-sg

Outbound:
- TCP 3306 to database-sg
- TCP 443 to 0.0.0.0/0 through NAT for package updates if required

## database-sg
Inbound:
- TCP 3306 from appserver-sg

No inbound internet rule.

## bastion-sg
Inbound:
- TCP 22 from your trusted admin IP only

Outbound:
- TCP 22 to webserver-sg
- TCP 22 to appserver-sg

Prefer SSM Session Manager instead of a public Bastion for a stronger production design.
