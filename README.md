# django_db_dumper

Bash script to easily dump a production database and seed a development one in a docker container

### 🚀 **Utilisation étape par étape**

#### **Étape 1 : Découverte automatique**
```bash
# 1. Modifiez les paramètres de connexion dans django_table_discovery.sh
chmod +x django_table_discovery.sh
./django_table_discovery.sh

# 2. Choisissez l'option 7 (analyse complète)
# → Génère automatiquement discovered_config.sh
```

#### **Étape 2 : Personnalisation**
```bash
# 1. Copiez le fichier généré
cp discovered_config.sh migration_config.sh

# 2. Éditez migration_config.sh pour :
#    - Ajuster le mot de passe
#    - Personnaliser les listes de tables
#    - Configurer votre conteneur Docker
```

#### **Étape 3 : Migration**
```bash
chmod +x django_migrator.sh
./django_migrator.sh

# Choisissez option 1 pour migration complète
```

### 🔧 **Exemple d'utilisation rapide**

Si vous voulez juste migrer quelques tables spécifiques :

```bash
# Dans migration_config.sh, définissez uniquement :
TABLES_TO_MIGRATE=(
    "auth_user"
    "myapp_product"
    "myapp_order"
)

SEQUENCES_TO_MIGRATE=(
    "auth_user_id_seq"
    "myapp_product_id_seq" 
    "myapp_order_id_seq"
)
```
