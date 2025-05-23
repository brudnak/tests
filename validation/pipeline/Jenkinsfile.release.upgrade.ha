#!groovy
node {
    def rootPath = "/root/go/src/github.com/rancher/tests/"
    def workPath = "/root/go/src/github.com/rancher/tests/validation/"

    def job_name = "${JOB_NAME}"
    if (job_name.contains('/')) { 
      job_names = job_name.split('/')
      job_name = job_names[job_names.size() - 1] 
    }

    def config = env.CONFIG
    def testContainer = "${job_name}${env.BUILD_NUMBER}_test"
    def setupContainer = "${job_name}${env.BUILD_NUMBER}_setup"
    def configGeneratorContainer = "${job_name}${env.BUILD_NUMBER}_generator"
    def cleanupContainer = "${job_name}${env.BUILD_NUMBER}_cleanup"
    def validationVolume = "ValidationSharedVolume-${job_name}${env.BUILD_NUMBER}"
    def testRancherVersions = "testrancherk8s.yaml"

    def imageName = "rancher-validation-${job_name}${env.BUILD_NUMBER}"

    def testsDir = "github.com/rancher/tests/validation/"
    def upgradeTestsDir = "${testsDir}upgrade"
    def provisioningTestsDir = "${testsDir}provisioning"

    def groovyEnvironments = "environments.groovy" 
    def configsDir = "cattle-configs"
    def patchedConfigsDir = "patched-cattle-configs"

    def testResultsOut = "results.xml"
    def envFile = ".env"
    def rancherConfig = "rancher_env.config"
    def branch = "main"
    def defaultTag = "validation"
    def localConfigFileName = ""

    if ("${env.BRANCH}" != "null" && "${env.BRANCH}" != "") {
      branch = "${env.BRANCH}"
    }
    def rancherRepo = scm.getUserRemoteConfigs()[0].getUrl()
    if ("${env.REPO}" != "null" && "${env.REPO}" != "") {
      rancherRepo = "${env.REPO}"
    }
    def timeout = "60m"
    if ("${env.TIMEOUT}" != "null" && "${env.TIMEOUT}" != "") {
      timeout = "${env.TIMEOUT}" 
    }

    def configFiles = []

    wrap([$class: 'AnsiColorBuildWrapper', 'colorMapName': 'XTerm', 'defaultFg': 2, 'defaultBg':1]) {
      withFolderProperties {
        paramsMap = []
        params.each {
          if (it.value && it.value.trim() != "") {
              paramsMap << "$it.key=$it.value"
          }
        }
        withCredentials([ string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'AWS_ACCESS_KEY_ID'),
                          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'AWS_SECRET_ACCESS_KEY'),
                          string(credentialsId: 'AWS_ACCESS_KEY_ID', variable: 'RANCHER_EKS_ACCESS_KEY'),
                          string(credentialsId: 'AWS_SECRET_ACCESS_KEY', variable: 'RANCHER_EKS_SECRET_KEY'),
                          string(credentialsId: 'DO_ACCESSKEY', variable: 'DO_ACCESSKEY'),
                          string(credentialsId: 'AWS_SSH_PEM_KEY', variable: 'AWS_SSH_PEM_KEY'),
                          string(credentialsId: 'RANCHER_SSH_KEY', variable: 'RANCHER_SSH_KEY'),
                          string(credentialsId: 'AZURE_SUBSCRIPTION_ID', variable: 'AZURE_SUBSCRIPTION_ID'),
                          string(credentialsId: 'AZURE_TENANT_ID', variable: 'AZURE_TENANT_ID'),
                          string(credentialsId: 'AZURE_CLIENT_ID', variable: 'AZURE_CLIENT_ID'),
                          string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'AZURE_CLIENT_SECRET'),
                          string(credentialsId: 'AZURE_AKS_SUBSCRIPTION_ID', variable: 'RANCHER_AKS_SUBSCRIPTION_ID'),
                          string(credentialsId: 'AZURE_TENANT_ID', variable: 'RANCHER_AKS_TENANT_ID'),
                          string(credentialsId: 'AZURE_CLIENT_ID', variable: 'RANCHER_AKS_CLIENT_ID'),
                          string(credentialsId: 'AZURE_CLIENT_SECRET', variable: 'RANCHER_AKS_SECRET_KEY'),
                          string(credentialsId: 'RANCHER_REGISTRY_USER_NAME', variable: 'RANCHER_REGISTRY_USER_NAME'),
                          string(credentialsId: 'RANCHER_REGISTRY_PASSWORD', variable: 'RANCHER_REGISTRY_PASSWORD'),
                          string(credentialsId: 'RANCHER_AD_SPECIAL_CHAR_PASSWORD', variable: 'RANCHER_AD_SPECIAL_CHAR_PASSWORD'),
                          string(credentialsId: 'ADMIN_PASSWORD', variable: 'ADMIN_PASSWORD'),
                          string(credentialsId: 'USER_PASSWORD', variable: 'USER_PASSWORD'),
                          string(credentialsId: 'RANCHER_GKE_CREDENTIAL', variable: 'RANCHER_GKE_CREDENTIAL'),
                          string(credentialsId: 'RANCHER_AUTH_USER_PASSWORD', variable: 'RANCHER_AUTH_USER_PASSWORD'),
                          string(credentialsId: 'RANCHER_HOSTNAME_OR_IP_ADDRESS', variable: 'RANCHER_HOSTNAME_OR_IP_ADDRESS'),
                          string(credentialsId: 'RANCHER_CA_CERTIFICATE', variable: 'RANCHER_CA_CERTIFICATE'),
                          string(credentialsId: 'RANCHER_SERVICE_ACCOUNT_NAME', variable: 'RANCHER_SERVICE_ACCOUNT_NAME'),
                          string(credentialsId: 'RANCHER_SERVICE_ACCOUNT_PASSWORD', variable: 'RANCHER_SERVICE_ACCOUNT_PASSWORD'),
                          string(credentialsId: 'RANCHER_USER_SEARCH_BASE', variable: 'RANCHER_USER_SEARCH_BASE'),
                          string(credentialsId: 'RANCHER_DEFAULT_LOGIN_DOMAIN', variable: 'RANCHER_DEFAULT_LOGIN_DOMAIN'),
                          string(credentialsId: 'RANCHER_OPENLDAP_SERVICE_ACCOUNT_NAME', variable: 'RANCHER_OPENLDAP_SERVICE_ACCOUNT_NAME'),
                          string(credentialsId: 'RANCHER_OPENLDAP_SERVICE_ACCOUNT_PASSWORD', variable: 'RANCHER_OPENLDAP_SERVICE_ACCOUNT_PASSWORD'),
                          string(credentialsId: 'RANCHER_OPENLDAP_USER_SEARCH_BASE', variable: 'RANCHER_OPENLDAP_USER_SEARCH_BASE'),
                          string(credentialsId: 'RANCHER_OPENLDAP_AUTH_USER_PASSWORD', variable: 'RANCHER_OPENLDAP_AUTH_USER_PASSWORD'),
                          string(credentialsId: 'RANCHER_OPENLDAP_HOSTNAME_OR_IP_ADDRESS', variable: 'RANCHER_OPENLDAP_HOSTNAME_OR_IP_ADDRESS'),
                          string(credentialsId: 'RANCHER_OPENLDAP_SPECIAL_CHAR_PASSWORD', variable: 'RANCHER_OPENLDAP_SPECIAL_CHAR_PASSWORD'),
                          string(credentialsId: 'RANCHER_FREEIPA_SERVICE_ACCOUNT_NAME', variable: 'RANCHER_FREEIPA_SERVICE_ACCOUNT_NAME'),
                          string(credentialsId: 'RANCHER_FREEIPA_SERVICE_ACCOUNT_PASSWORD', variable: 'RANCHER_FREEIPA_SERVICE_ACCOUNT_PASSWORD'),
                          string(credentialsId: 'RANCHER_FREEIPA_USER_SEARCH_BASE', variable: 'RANCHER_FREEIPA_USER_SEARCH_BASE'),
                          string(credentialsId: 'RANCHER_FREEIPA_GROUP_SEARCH_BASE', variable: 'RANCHER_FREEIPA_GROUP_SEARCH_BASE'),
                          string(credentialsId: 'RANCHER_FREEIPA_AUTH_USER_PASSWORD', variable: 'RANCHER_FREEIPA_AUTH_USER_PASSWORD'),
                          string(credentialsId: 'RANCHER_FREEIPA_HOSTNAME_OR_IP_ADDRESS', variable: 'RANCHER_FREEIPA_HOSTNAME_OR_IP_ADDRESS'),
                          string(credentialsId: 'RANCHER_FREEIPA_SPECIAL_CHAR_PASSWORD', variable: 'RANCHER_FREEIPA_SPECIAL_CHAR_PASSWORD'),
                          string(credentialsId: 'RANCHER_VALID_TLS_CERT', variable: 'RANCHER_VALID_TLS_CERT'),
                          string(credentialsId: 'RANCHER_VALID_TLS_KEY', variable: 'RANCHER_VALID_TLS_KEY'),
                          string(credentialsId: 'RANCHER_BYO_TLS_CERT', variable: 'RANCHER_BYO_TLS_CERT'),
                          string(credentialsId: 'RANCHER_BYO_TLS_KEY', variable: 'RANCHER_BYO_TLS_KEY'),
                          string(credentialsId: 'RANCHER_LINODE_ACCESSKEY', variable: "RANCHER_LINODE_ACCESSKEY")]) {
        withEnv(paramsMap) {
          stage('Checkout') {
            deleteDir()
            checkout([
                      $class: 'GitSCM',
                      branches: [[name: "*/${branch}"]],
                      extensions: scm.extensions + [[$class: 'CleanCheckout']],
                      userRemoteConfigs: [[url: rancherRepo]]
                    ])
          }
          dir ("./") {
            try {
              stage('Configure and Build') {
                config = config.replace('${AWS_SECRET_ACCESS_KEY}', env.AWS_SECRET_ACCESS_KEY)
                config = config.replace('${AWS_ACCESS_KEY_ID}', env.AWS_ACCESS_KEY_ID)
                if (env.AWS_SSH_PEM_KEY && env.AWS_SSH_KEY_NAME) {
                  dir("./validation/.ssh") {
                    def decoded = new String(AWS_SSH_PEM_KEY.decodeBase64())
                    writeFile file: AWS_SSH_KEY_NAME, text: decoded
                  }
                }
                
                try{
                  sh "./validation/build.sh"
                  
                  sh "docker volume create --name ${validationVolume}"

                  sh "docker run -v ${validationVolume}:/root  --name ${setupContainer} -t -e RANCHER_VERSION=\$RANCHER_VERSION " +
                  " -e RANCHER_VERSION_TO_UPGRADE=\$RANCHER_VERSION_TO_UPGRADE " +
                  "${imageName} sh -c \"${workPath}pipeline/scripts/rancher_k8s_version.sh\""

                  sh "docker cp ${setupContainer}:/root/go/src/github.com/rancher/tests/testrancherk8s.yaml ./"

                  println "contents of test rancher versions: ./${testRancherVersions}"
                  
                 def rancherRKE2Version = sh(
                      script: "grep -E '^rancherRKE2Version:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher RKE2 version ${rancherRKE2Version}"


                  def rancherRKE2VersionToUpgrade = sh(
                      script: "grep 'rancherRKE2VersionToUpgrade' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher RKE2 version to upgrade ${rancherRKE2VersionToUpgrade}"
                  
                  def rancherK3sVersion = sh(
                      script: "grep -E '^rancherK3sVersion:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher K3s version ${rancherK3sVersion}"
                  
                  def rancherK3sVersionToUpgrade = sh(
                      script: "grep 'rancherK3sVersionToUpgrade' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher K3s version to upgrade ${rancherK3sVersionToUpgrade}"
                  
                  def rancherRKEVersion = sh(
                      script: "grep -E '^rancherRKEVersion:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher RKE version ${rancherRKEVersion}"
                  
                  def rancherRKEVersionToUpgrade = sh(
                      script: "grep 'rancherRKEVersionToUpgrade' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher RKE version to upgrade ${rancherRKEVersionToUpgrade}"
                  
                  def rancherVersion = sh(
                      script: "grep 'rancherVersion:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher version ${rancherVersion}"
                  
                  def rancherImageTag = sh(
                      script: "grep 'rancherImageTag:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher rancher image tag version ${rancherImageTag}"

                  def rancherVersionToUpgrade = sh(
                      script: "grep 'rancherVersionToUpgrade:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher version to upgrade ${rancherVersionToUpgrade}"
                  
                  def rancherImageTagToUpgrade = sh(
                      script: "grep 'rancherImageTagToUpgrade:' ./${testRancherVersions} | awk '{print \$2}'",
                      returnStdout: true
                    ).trim()
                  println "Rancher image tag to upgrade version ${rancherImageTagToUpgrade}"

                config = config.replace('${RANCHER_RKE2_VERSION}', rancherRKE2Version)
                config = config.replace('${RANCHER_RKE2_VERSION_TO_UPGRADE}', rancherRKE2VersionToUpgrade)
                config = config.replace('${RANCHER_K3S_VERSION}', rancherK3sVersion)
                config = config.replace('${RANCHER_K3S_VERSION_TO_UPGRADE}', rancherK3sVersionToUpgrade)
                config = config.replace('${RANCHER_RKE_VERSION}', rancherRKEVersion)
                config = config.replace('${RANCHER_RKE_VERSION_TO_UPGRADE}', rancherRKEVersionToUpgrade)
                config = config.replace('${RANCHER_VERSION}', rancherVersion)
                config = config.replace('${RANCHER_IMAGE_TAG}', rancherImageTag)
                config = config.replace('${RANCHER_VERSION_TO_UPGRADE}', rancherVersionToUpgrade)
                config = config.replace('${RANCHER_IMAGE_TAG_TO_UPGRADE}', rancherImageTagToUpgrade)
                }catch (err){
                    sh "docker stop ${setupContainer}"
                    sh "docker rm -v ${setupContainer}"
                    sh "docker volume rm -f ${validationVolume}"
                    sh "docker rmi ${imageName}"
                  }


                sh "docker stop ${setupContainer}"
                sh "docker rm -v ${setupContainer}"
                sh "docker volume rm -f ${validationVolume}"
                sh "docker rmi ${imageName}"


                dir("./validation") {
                  def filename = "config.yaml"

                  writeFile file: filename, text: config
                  env.CATTLE_TEST_CONFIG = workPath+filename
                }

                sh "./validation/configure.sh"
                sh "./validation/build.sh"
              }
              stage('Setup') {
                sh returnStdout: true, script: 'wget -qO ./yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64'
                sh returnStdout:true, script: 'chmod a+x ./yq'

                def initConfigPath = "./validation/config.yaml"

                env.HA_HOST= sh (
                  script: "./yq '.ha.host' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA host: ${env.HA_HOST}"

                env.HA_HOST_PREFIX= (env.HA_HOST.substring(0, env.HA_HOST.indexOf('.'))).trim()
                println "HA host Prefix: ${env.HA_HOST_PREFIX}"

                env.HA_CHART_VERSION= sh (
                  script: "./yq '.ha.chartVersion' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println " HA chart version: ${env.HA_CHART_VERSION}"

                env.HA_CHART_VERSION_TO_UPGRADE= sh (
                  script: "./yq '.ha.chartVersionToUpgrade' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA chart version to upgrade: ${env.HA_CHART_VERSION_TO_UPGRADE}"

                 env.HA_IMAGE_TAG= sh (
                  script: "./yq '.ha.imageTag' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA image tag: ${env.HA_IMAGE_TAG}"

                 env.HA_IMAGE_TAG_TO_UPGRADE= sh (
                  script: "./yq '.ha.imageTagToUpgrade' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA image tag to upgrade: ${env.HA_IMAGE_TAG_TO_UPGRADE}"

                env.HA_HELM_REPO= sh (
                  script: "./yq '.ha.helmRepo' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA helm repo: ${env.HA_HELM_REPO}"

                env.HA_HELM_REPO_TO_UPGRADE= sh (
                  script: "./yq '.ha.helmRepoToUpgrade' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA helm repo to upgrade: ${env.HA_HELM_REPO_TO_UPGRADE}"

                env.HA_HELM_URL= sh (
                  script: "./yq '.ha.helmURL' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA helm url: ${env.HA_HELM_URL}"

                env.HA_HELM_URL_TO_UPGRADE= sh (
                  script: "./yq '.ha.helmURLToUpgrade' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA helm url to upgrade: ${env.HA_HELM_URL_TO_UPGRADE}"

                env.RKE_VERSION= sh (
                  script: "./yq '.ha.rkeVersion' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "RKE version: ${env.RKE_VERSION}"

                env.HA_CERT_OPTION= sh (
                  script: "./yq '.ha.certOption' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA cert option: ${env.HA_CERT_OPTION}"

                env.RANCHER_HA_HARDENED= sh (
                  script: "./yq '.ha.hardened' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA hardened option: ${env.RANCHER_HA_HARDENED}"

                env.RANCHER_PSP_ENABLED= sh (
                  script: "./yq '.ha.pspEnabled' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA PSP enabled option: ${env.RANCHER_PSP_ENABLED}"
                
                env.RANCHER_HELM_EXTRA_SETTINGS= sh (
                  script: "./yq '.ha.helmExtraSettings' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA Helm extra settings option: ${env.RANCHER_HELM_EXTRA_SETTINGS}"

                env.RANCHER_HELM_EXTRA_SETTINGS_TO_UPGRADE= sh (
                  script: "./yq '.ha.helmExtraSettingsToUpgrade' ${initConfigPath}",
                  returnStdout: true
                ).trim()
                println "HA Helm extra settings option to be used on an upgrade: ${env.RANCHER_HELM_EXTRA_SETTINGS_TO_UPGRADE}"

                env.HA_CLEANUP= sh (
                  script: "./yq '.ha.cleanup' ${initConfigPath}",
                  returnStdout: true
                ).trim()

                if ("${env.HA_CLEANUP}" == "" || "${env.HA_CLEANUP}" == "null") {
                    env.HA_CLEANUP=true
                }
                println "HA cleanup: ${env.HA_CLEANUP}"
              }
              stage('Deploys Rancher on a specified version') {
                deployParams = [
                 string(name: 'RANCHER_HOSTNAME_PREFIX', value: "${env.HA_HOST_PREFIX}"),
                 string(name: 'RANCHER_CHART_VERSION', value: "${env.HA_CHART_VERSION}"),
                 string(name: 'RANCHER_IMAGE_TAG', value: "${env.HA_IMAGE_TAG}"),
                 string(name: 'RANCHER_HELM_REPO', value: "${env.HA_HELM_REPO}"),
                 string(name: 'RANCHER_HELM_URL', value: "${env.HA_HELM_URL}"),
                 string(name: 'RANCHER_HA_CERT_OPTION', value: "${env.HA_CERT_OPTION}"),
                 string(name: 'RKE_VERSION', value: "${env.RKE_VERSION}"),
                 string(name: 'RANCHER_HA_HARDENED', value: "${env.RANCHER_HA_HARDENED}"),
                 string(name: 'RANCHER_PSP_ENABLED', value: "${env.RANCHER_PSP_ENABLED}"),
                 string(name: 'RANCHER_HELM_EXTRA_SETTINGS', value: "${env.RANCHER_HELM_EXTRA_SETTINGS}")
                ]

              build job: 'rancher-v3_ha_deploy', parameters: deployParams
              }
              stage('Post Rancher Install Configuration') {
                sh "docker run --name ${setupContainer} -t -e HA_HOST=\$HA_HOST -e ADMIN_PASSWORD=\$ADMIN_PASSWORD " +
                  "${imageName} sh -c \"${workPath}pipeline/hapostinstall/hapostinstall.sh\""

                // load HA_KUBECONFIG and HA_TOKEN
                sh "docker cp ${setupContainer}:${rootPath}${groovyEnvironments} ."
                load groovyEnvironments
              }
              stage ('Generate configuration files') {
                sh "docker run --name ${configGeneratorContainer} -t -e HA_TOKEN=\$HA_TOKEN -e CATTLE_TEST_CONFIG=\$CATTLE_TEST_CONFIG " +
                  "${imageName} sh -c \"${workPath}pipeline/releaseupgrade/releaseupgrade.sh\""

                sh "docker cp ${configGeneratorContainer}:${rootPath}${configsDir}/ ."

                def configs = sh(script: "ls -1 ./${configsDir}", returnStdout: true).split()

                for (int i = 0; i < configs.size(); i++) {
                  def configName = configs[i]
                  if (configName.contains('local')) {
                    echo "skipping pushing local to the global variable"
                    localConfigFileName = "$configName"
                    continue
                  }
                  echo "pushing ${configName} to the global variable"
                  configFiles << "${configName}"
                }
                
                dir("./${patchedConfigsDir}") {
                  sh "docker cp ${configGeneratorContainer}:${rootPath}${configsDir}/${localConfigFileName} ."
                }

                println "Removing the tagged image"
                sh "docker rmi -f ${imageName}"

                println "Building the image again with the config files"
                sh "./validation/build.sh"
                sh "./validation/configure.sh"
              }
              stage('Deploys clusters') {
                try {
                 jobs = [:]

                 configFiles.each {
                   def configPath = "./${configsDir}/$it"
                   def absoluteConfigPath = "${rootPath}${configsDir}/$it"
                   
                   def testCase = sh (
                     script: "./yq '.testCases.provisioningTestCase'  ${configPath}",
                     returnStdout: true
                   ).trim()

                   def testPackage = sh (
                     script: "./yq '.testCases.provisioningTestPackage'  ${configPath}",
                     returnStdout: true
                   ).trim()

                   jobs["$it-provisioning"] = { 
                     stage("Parallel Provisioning: $it"){
                       def containerName = "${job_name}${env.BUILD_NUMBER}_$it-provisioning"
                       try {
                         sh "docker run --name ${containerName} -t -e CATTLE_TEST_CONFIG=\"${absoluteConfigPath}\" " +
                       "${imageName} sh -c \"/root/go/bin/gotestsum --format standard-verbose --packages=\"${testsDir}${testPackage}\" --junitfile ${testResultsOut} -- -tags=validation ${testCase} -timeout=\"60m\" -v\""

                        dir("./${patchedConfigsDir}") {
                          sh "docker cp ${containerName}:${rootPath}${configsDir}/$it ."
                        }
                       } catch (err){
                         sh "docker stop ${containerName}"
                         sh "docker rm -v ${containerName}"
                       }

                       sh "docker stop ${containerName}"
                       sh "docker rm -v ${containerName}"
                     }
                   }
                }

                parallel jobs
                } catch(err){
                  echo "Provisioning tests had failures: " + err
                }
              }
              stage('Cluster names mapping') {
                configFiles.each {
                  try{
                    sh (
                      script: "./yq -i '.upgradeInput.clusters[0].name = .rancher.clusterName' ./${patchedConfigsDir}/$it",
                      returnStdout: true
                    )
                  } catch(err){
                  echo "Cluster mapping had failures: " + err
                  }
                }
                echo "pushing ${localConfigFileName} to the global variable"
                configFiles << "${localConfigFileName}"
              }
              stage('Run preupgrade checks') {
                try {
                  jobs = [:]
                  configFiles.each {
                    try {
                      def configPath = "./${configsDir}/$it"
                      def configYaml = readFile(file: "./${patchedConfigsDir}/$it")

                      def testCase = sh (
                        script: "./yq '.testCases.preUpgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def testPackage = sh (
                        script: "./yq '.testCases.upgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def goValidationParams = [
                        string(name: 'TIMEOUT', value: "30m"),
                        text(name: 'CONFIG', value: configYaml),
                        string(name: 'REPO', value: "${rancherRepo}"),
                        string(name: 'BRANCH', value: "${branch}"),
                        string(name: 'TEST_PACKAGE', value: "${testPackage}"),
                        string(name: 'TAGS', value: "${defaultTag}"),
                        string(name: 'GOTEST_TESTCASE', value: "${testCase}")
                      ]

                      jobs["$it-preupgrade"] = { build job: 'go-automation-freeform-job', parameters: goValidationParams }
                    } catch(err) {
                      echo "Pre upgrade $it had failures: " + err
                    }
                  }

                  parallel jobs
                } catch(err) {
                  echo "Pre upgrade tests had failures: " + err
                }
              }
              stage('Upgrade Rancher') {
                upgradeParams = [
                string(name: 'RANCHER_HA_HOSTNAME', value: "${env.HA_HOST}"),
                string(name: 'RANCHER_CHART_VERSION', value: "${env.HA_CHART_VERSION_TO_UPGRADE}"),
                string(name: 'RANCHER_IMAGE_TAG', value: "${env.HA_IMAGE_TAG_TO_UPGRADE}"),
                string(name: 'RANCHER_HELM_REPO', value: "${env.HA_HELM_REPO_TO_UPGRADE}"),
                string(name: 'RANCHER_HELM_URL', value: "${env.HA_HELM_URL_TO_UPGRADE}"),
                string(name: 'RANCHER_HA_CERT_OPTION', value: "${env.HA_CERT_OPTION}"),
                string(name: 'RANCHER_HA_KUBECONFIG', value: "${env.HA_KUBECONFIG}"),
                string(name: 'RANCHER_HELM_EXTRA_SETTINGS', value: "${env.RANCHER_HELM_EXTRA_SETTINGS_TO_UPGRADE}")
               ]

                build job: 'rancher-v3_ha_upgrade', parameters: upgradeParams
              }

              stage('Run postupgrade checks') {
                try {
                  jobs = [:]

                  configFiles.each {
                    try {
                      def configPath = "./${configsDir}/$it"
                      def configYaml = readFile(file: "./${patchedConfigsDir}/$it")

                      def testCase = sh (
                        script: "./yq '.testCases.postUpgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def testPackage = sh (
                        script: "./yq '.testCases.upgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def goValidationParams = [
                        string(name: 'TIMEOUT', value: "30m"),
                        text(name: 'CONFIG', value: configYaml),
                        string(name: 'REPO', value: "${rancherRepo}"),
                        string(name: 'BRANCH', value: "${branch}"),
                        string(name: 'TEST_PACKAGE', value: "${testPackage}"),
                        string(name: 'TAGS', value: "${defaultTag}"),
                        string(name: 'GOTEST_TESTCASE', value: "${testCase}")
                      ]

                      jobs["$it-postupgrade"] = { build job: 'go-automation-freeform-job', parameters: goValidationParams }
                    } catch(err) {
                      echo "Post upgrade $it had failures: " + err
                    }
                  }

                  parallel jobs
                } catch(err){
                  echo "Post upgrade tests had failures: " + err
                }
              }
              stage('Upgrade cluster versions') {
                try{
                  jobs = [:]

                  configFiles.each {
                    try {
                      def configPath = "./${configsDir}/$it"
                      def configYaml = readFile(file: "./${patchedConfigsDir}/$it")

                      def testCase = sh (
                        script: "./yq '.testCases.upgradeKubernetesTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def testPackage = sh (
                        script: "./yq '.testCases.upgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def goValidationParams = [
                        string(name: 'TIMEOUT', value: "2h"),
                        text(name: 'CONFIG', value: configYaml),
                        string(name: 'REPO', value: "${rancherRepo}"),
                        string(name: 'BRANCH', value: "${branch}"),
                        string(name: 'TEST_PACKAGE', value: "${testPackage}"),
                        string(name: 'TAGS', value: "${defaultTag}"),
                        string(name: 'GOTEST_TESTCASE', value: "${testCase}" )
                      ]

                      jobs["$it-k8supgrade"] = { build job: 'go-automation-freeform-job', parameters: goValidationParams }
                    } catch(err){
                      echo "Kubernetes upgrade $it had failures: " + err
                    }
                  }

                  parallel jobs
                } catch(err){
                  echo "Kubernetes upgrade tests had failures: " + err
                }
              }
              stage('Run postupgrade checks') {
                try{
                  jobs = [:]

                  configFiles.each {
                    try{
                      def configPath = "./${configsDir}/$it"
                      def configYaml = readFile(file: "./${patchedConfigsDir}/$it")

                      def testCase = sh (
                        script: "./yq '.testCases.postUpgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def testPackage = sh (
                        script: "./yq '.testCases.upgradeTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def goValidationParams = [
                        string(name: 'TIMEOUT', value: "30m"),
                        text(name: 'CONFIG', value: configYaml),
                        string(name: 'REPO', value: "${rancherRepo}"),
                        string(name: 'BRANCH', value: "${branch}"),
                        string(name: 'TEST_PACKAGE', value: "${testPackage}"),
                        string(name: 'TAGS', value: "${defaultTag}"),
                        string(name: 'GOTEST_TESTCASE', value: "${testCase}")
                      ]

                      jobs["$it-postupgrade"] = { build job: 'go-automation-freeform-job', parameters: goValidationParams }
                    } catch(err){
                      echo "Post upgrade test $it had failures: " + err
                    }
                  }

                  parallel jobs
                } catch(err){
                  echo "Post upgrade tests had failures: " + err
                }
              }
              stage('Deploy new clusters') {
                try {
                  jobs = [:]

                  configFiles.each {
                    try{
                      def configPath = "./${configsDir}/$it"
                      def configYaml = readFile(file: "${configPath}")

                      def testCase = sh (
                        script: "./yq '.testCases.provisioningTestCase'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def testPackage = sh (
                        script: "./yq '.testCases.provisioningTestPackage'  ${configPath}",
                        returnStdout: true
                      ).trim()

                      def goValidationParams = [
                        string(name: 'TIMEOUT', value: "1h"),
                        text(name: 'CONFIG', value: configYaml),
                        string(name: 'REPO', value: "${rancherRepo}"),
                        string(name: 'BRANCH', value: "${branch}"),
                        string(name: 'TEST_PACKAGE', value: "${testPackage}"),
                        string(name: 'TAGS', value: "${defaultTag}"),
                        string(name: 'GOTEST_TESTCASE', value: "${testCase}")
                      ]

                      jobs["$it-provisioning"] = { build job: 'go-automation-freeform-job', parameters: goValidationParams }
                    } catch(err){
                      echo "Deploy new cluster test $it had failures: " + err
                    }
                  }

                  parallel jobs
                } catch(err){
                  echo "Deploy new clusters tests had failures: " + err
                }
              }
              stage('Delete Rancher and resources') {
                if (env.HA_CLEANUP.toBoolean()) {
                  try{
                    sh 'echo Cleanup is enabled'

                    sh "docker run --name ${cleanupContainer} -t -e HA_HOST=\$HA_HOST -e ADMIN_PASSWORD=\$ADMIN_PASSWORD " +
                      "${imageName} sh -c \"${workPath}pipeline/downstreamcleanup/downstreamcleanup.sh\""

                    deleteParams = [
                      string(name: 'CATTLE_TEST_URL', value: "http://${env.HA_HOST}")
                    ]

                    build job: 'rancher-v3_ha_delete', parameters: deleteParams

                    sh "docker stop ${cleanupContainer}"
                    sh "docker rm -v ${cleanupContainer}"
                  } catch(err){
                    echo "Cleanup had failures: " + err
                  }
                } else {
                  sh 'echo Cleanup is disabled'
                }
              }
              stage('Test Report') {
                sh "docker stop ${setupContainer}"
                sh "docker rm -v ${setupContainer}"

                sh "docker stop ${configGeneratorContainer}"
                sh "docker rm -v ${configGeneratorContainer}"

                sh "docker rmi -f ${imageName}"
              }
            } catch(err) {           
              echo "Caught: ${err}"
              stage('Delete Rancher and resources in error') {
                if (env.HA_CLEANUP.toBoolean()) {
                  try {
                    sh 'echo Cleanup is enabled'

                    sh "docker run --name ${cleanupContainer} -t -e HA_HOST=\$HA_HOST -e ADMIN_PASSWORD=\$ADMIN_PASSWORD " +
                      "${imageName} sh -c \"${workPath}pipeline/downstreamcleanup/downstreamcleanup.sh\""

                    deleteParams = [
                      string(name: 'CATTLE_TEST_URL', value: "http://${env.HA_HOST}")
                    ]

                    build job: 'rancher-v3_ha_delete', parameters: deleteParams

                    sh "docker stop ${cleanupContainer}"
                    sh "docker rm -v ${cleanupContainer}"
                  } catch(error) {
                    echo "Cleanup had failures: " + error
                  }
                } else {
                  sh 'echo Cleanup is disabled'
                }
              }
                sh "docker stop ${setupContainer}"
                sh "docker rm -v ${setupContainer}"

                sh "docker stop ${configGeneratorContainer}"
                sh "docker rm -v ${configGeneratorContainer}"

                sh "docker rmi -f ${imageName}"
            } // catch error
          } // dir 
        } // withEnv
      } // creds
    } // folder properties
  } // wrap 
} // node