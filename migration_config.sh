# ===============================================
# CONFIGURATION DE MIGRATION DJANGO
# Fichier: migration_config.sh
# ===============================================

# ===============================================
# PARAMÈTRES DE CONNEXION
# ===============================================

# Base de données de production
export PROD_HOST="votre_serveur_prod.com"
export PROD_PORT="5432"
export PROD_DB="myapp_production"
export PROD_USER="myapp_user"
export PROD_PASSWORD="votre_mot_de_passe_prod"

# Conteneur de développement
export DEV_CONTAINER="myapp_postgres_dev"
export DEV_DB="myapp_development"
export DEV_USER="postgres"

# ===============================================
# TABLES DJANGO À MIGRER
# ===============================================

# Tables de base Django (généralement nécessaires)
DJANGO_BASE_TABLES=(
    "django_migrations"
    "django_content_type"
    "auth_permission"
    "auth_group"
    "auth_group_permissions"
    "auth_user"
    "auth_user_groups"
    "auth_user_user_permissions"
)

# Tables de votre application (à personnaliser)
YOUR_APP_TABLES=(
    # Exemple pour une app "blog"
    "blog_category"
    "blog_post"
    "blog_comment"
    "blog_tag"
    "blog_post_tags"
    
    # Exemple pour une app "ecommerce"
    "ecommerce_product"
    "ecommerce_order"
    "ecommerce_orderitem"
    "ecommerce_customer"
    
    # Exemple pour une app "cms"
    "cms_page"
    "cms_menu"
    "cms_content"
    
    # Ajoutez vos tables ici...
    # "votre_app_model1"
    # "votre_app_model2"
)

# Tables de session et cache (optionnel - souvent pas nécessaire en dev)
SESSION_TABLES=(
    # "django_session"  # Décommentez si vous voulez migrer les sessions
    # "django_cache_table"  # Si vous utilisez le cache en base
)

# Combiner toutes les tables
TABLES_TO_MIGRATE=(
    "${DJANGO_BASE_TABLES[@]}"
    "${YOUR_APP_TABLES[@]}"
    "${SESSION_TABLES[@]}"
)

# ===============================================
# SÉQUENCES À MIGRER
# ===============================================

# Séquences Django de base
DJANGO_BASE_SEQUENCES=(
    "django_content_type_id_seq"
    "auth_permission_id_seq"
    "auth_group_id_seq"
    "auth_user_id_seq"
)

# Séquences de votre application
YOUR_APP_SEQUENCES=(
    # Exemple pour une app "blog"
    "blog_category_id_seq"
    "blog_post_id_seq"
    "blog_comment_id_seq"
    "blog_tag_id_seq"
    
    # Exemple pour une app "ecommerce"
    "ecommerce_product_id_seq"
    "ecommerce_order_id_seq"
    "ecommerce_orderitem_id_seq"
    "ecommerce_customer_id_seq"
    
    # Exemple pour une app "cms"
    "cms_page_id_seq"
    "cms_menu_id_seq"
    "cms_content_id_seq"
    
    # Ajoutez vos séquences ici...
    # "votre_app_model1_id_seq"
    # "votre_app_model2_id_seq"
)

# Combiner toutes les séquences
SEQUENCES_TO_MIGRATE=(
    "${DJANGO_BASE_SEQUENCES[@]}"
    "${YOUR_APP_SEQUENCES[@]}"
)

# ===============================================
# TABLES À VIDER AVANT INSERTION
# ===============================================

# Tables qu'il est souvent préférable de vider en développement
TABLES_TO_TRUNCATE=(
    "django_session"        # Sessions utilisateur
    "django_admin_log"      # Logs d'administration
    # "auth_user"           # Décommentez si vous voulez réinitialiser les utilisateurs
)

# ===============================================
# OPTIONS AVANCÉES
# ===============================================

# Ordre de restauration des tables (important pour les contraintes FK)
# Si vous avez des dépendances complexes, spécifiez l'ordre ici
RESTORATION_ORDER=(
    # Tables sans dépendances d'abord
    "django_content_type"
    "auth_permission"
    "auth_group"
    "auth_user"
    
    # Puis tables avec FK
    "auth_group_permissions"
    "auth_user_groups"
    "auth_user_user_permissions"
    
    # Vos tables dans l'ordre de dépendance
    "blog_category"
    "blog_tag"
    "blog_post"
    "blog_post_tags"
    "blog_comment"
)

# Tables sensibles (affichage d'un avertissement avant migration)
SENSITIVE_TABLES=(
    "auth_user"             # Données utilisateurs
    "auth_user_user_permissions"  # Permissions
    "your_sensitive_table"  # Vos tables sensibles
)

# ===============================================
# COMMANDES DE GÉNÉRATION AUTOMATIQUE
# ===============================================

# Fonction pour générer la liste des tables à partir des modèles Django
generate_tables_from_django() {
    echo "# Tables générées automatiquement depuis Django"
    echo "# Exécutez cette commande dans votre projet Django:"
    echo ""
    echo "python manage.py shell -c \""
    echo "from django.apps import apps"
    echo "for model in apps.get_models():"
    echo "    print(f'{model._meta.db_table}')"
    echo "\""
    echo ""
    echo "# Puis copiez la sortie dans YOUR_APP_TABLES"
}

# Fonction pour générer la liste des séquences
generate_sequences_from_tables() {
    echo "# Séquences générées automatiquement"
    echo "# Pour PostgreSQL, ajoutez '_id_seq' au nom de table pour les clés primaires"
    echo ""
    for table in "${YOUR_APP_TABLES[@]}"; do
        echo "\"${table}_id_seq\""
    done
}

# ===============================================
# VALIDATION DE LA CONFIGURATION
# ===============================================

validate_config() {
    echo "🔍 Validation de la configuration..."
    echo ""
    echo "📊 Statistiques:"
    echo "   - Tables Django de base: ${#DJANGO_BASE_TABLES[@]}"
    echo "   - Tables de votre app: ${#YOUR_APP_TABLES[@]}"
    echo "   - Tables session: ${#SESSION_TABLES[@]}"
    echo "   - Total tables: ${#TABLES_TO_MIGRATE[@]}"
    echo ""
    echo "   - Séquences Django: ${#DJANGO_BASE_SEQUENCES[@]}"
    echo "   - Séquences de votre app: ${#YOUR_APP_SEQUENCES[@]}"
    echo "   - Total séquences: ${#SEQUENCES_TO_MIGRATE[@]}"
    echo ""
    echo "   - Tables à vider: ${#TABLES_TO_TRUNCATE[@]}"
    echo ""
    
    # Vérifier les tables sensibles
    if [ ${#SENSITIVE_TABLES[@]} -gt 0 ]; then
        echo "⚠️  Tables sensibles détectées:"
        for table in "${SENSITIVE_TABLES[@]}"; do
            echo "   - $table"
        done
        echo ""
    fi
}

# ===============================================
# HELPERS POUR DJANGO
# ===============================================

# Commande pour afficher les tables Django actuelles
show_django_tables() {
    echo "# Commandes pour inspecter votre base Django:"
    echo ""
    echo "# 1. Se connecter à la base de prod"
    echo "psql -h $PROD_HOST -p $PROD_PORT -U $PROD_USER -d $PROD_DB"
    echo ""
    echo "# 2. Lister toutes les tables"
    echo "\\dt"
    echo ""
    echo "# 3. Lister les tables par app Django"
    echo "SELECT schemaname, tablename FROM pg_tables WHERE tablename LIKE 'votre_app_%';"
    echo ""
    echo "# 4. Lister les séquences"
    echo "\\ds"
    echo ""
    echo "# 5. Compter les lignes par table"
    echo "SELECT schemaname, tablename, n_tup_ins-n_tup_del as rows"
    echo "FROM pg_stat_user_tables"
    echo "WHERE schemaname = 'public'"
    echo "ORDER BY rows DESC;"
}

# Si ce fichier est exécuté directement, afficher les infos
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_config
    echo ""
    echo "💡 Pour utiliser cette configuration:"
    echo "   source migration_config.sh"
    echo "   ./django_migrator.sh"
    echo ""
    echo "🔧 Pour personnaliser:"
    echo "   1. Modifiez YOUR_APP_TABLES avec vos tables"
    echo "   2. Modifiez YOUR_APP_SEQUENCES avec vos séquences"
    echo "   3. Ajustez les paramètres de connexion"
fi