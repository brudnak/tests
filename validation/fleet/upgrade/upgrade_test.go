package upgrade

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/rancher/fleet/pkg/apis/fleet.cattle.io/v1alpha1"
	provv1 "github.com/rancher/rancher/pkg/apis/provisioning.cattle.io/v1"
	"github.com/rancher/shepherd/clients/rancher"
	management "github.com/rancher/shepherd/clients/rancher/generated/management/v3"
	steveV1 "github.com/rancher/shepherd/clients/rancher/v1"
	extensionClusters "github.com/rancher/shepherd/extensions/clusters"
	extensionsfleet "github.com/rancher/shepherd/extensions/fleet"
	"github.com/rancher/shepherd/pkg/namegenerator"
	"github.com/rancher/shepherd/pkg/nodes"
	"github.com/rancher/shepherd/pkg/session"
	projectsapi "github.com/rancher/tests/actions/projects"
	"github.com/rancher/tests/actions/ssh"
	"github.com/rancher/tests/interoperability/fleet"
	log "github.com/sirupsen/logrus"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
)

type UpgradeTestSuite struct {
	suite.Suite
	client          *rancher.Client
	session         *session.Session
	cluster         *management.Cluster
	clusterName     string
	sshNode         *nodes.Node
	fleetSecretName string
}

func (u *UpgradeTestSuite) TearDownSuite() {
	u.session.Cleanup()
}

func (u *UpgradeTestSuite) SetupSuite() {
	u.session = session.NewSession()

	client, err := rancher.NewClient("", u.session)
	require.NoError(u.T(), err)

	u.client = client

	log.Info("Getting cluster name from the config file and append cluster details in connection")
	clusterName := client.RancherConfig.ClusterName
	require.NotEmptyf(u.T(), clusterName, "Cluster name to install should be set")

	clusterID, err := extensionClusters.GetClusterIDByName(u.client, clusterName)
	require.NoError(u.T(), err, "Error getting cluster ID")

	u.cluster, err = u.client.Management.Cluster.ByID(clusterID)
	require.NoError(u.T(), err)

	provisioningClusterID, err := extensionClusters.GetV1ProvisioningClusterByName(client, clusterName)
	require.NoError(u.T(), err)

	cluster, err := client.Steve.SteveType(extensionClusters.ProvisioningSteveResourceType).ByID(provisioningClusterID)
	require.NoError(u.T(), err)

	newCluster := &provv1.Cluster{}
	err = steveV1.ConvertToK8sType(cluster, newCluster)
	require.NoError(u.T(), err)

	u.clusterName = client.RancherConfig.ClusterName
	if !strings.Contains(newCluster.Spec.KubernetesVersion, "k3s") && !strings.Contains(newCluster.Spec.KubernetesVersion, "rke2") {
		u.clusterName = u.cluster.ID
	}

	u.sshNode, err = ssh.CreateSSHNode(u.client, u.cluster.Name, u.cluster.ID)
	require.NoError(u.T(), err)

	u.fleetSecretName, err = createFleetSSHSecret(u.client, u.sshNode.SSHKey)
	require.NoError(u.T(), err)
}

func (u *UpgradeTestSuite) TestNewCommitFleetRepo() {
	u.session = session.NewSession()

	log.Info("Creating new project and namespace")
	_, namespace, err := projectsapi.CreateProjectAndNamespace(u.client, u.cluster.ID)
	require.NoError(u.T(), err)

	log.Info("Cloning Git Repo")
	repoName := namegenerator.AppendRandomString("repo-name")
	_, err = u.sshNode.ExecuteCommand(fmt.Sprintf("cd ~/ && git clone %s %s", fleet.ExampleRepo, repoName))
	require.NoError(u.T(), err)

	log.Info("Creating Fleet repo")
	repoObject, err := createLocalFleetGitRepo(u.client, u.sshNode, repoName, namespace.Name, u.clusterName, u.cluster.ID, u.fleetSecretName)
	require.NoError(u.T(), err)

	log.Info("Getting GitRepoStatus")
	gitRepo, err := u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	gitStatus := &v1alpha1.GitRepoStatus{}
	err = steveV1.ConvertToK8sType(gitRepo.Status, gitStatus)
	require.NoError(u.T(), err)

	err = gitPushCommit(u.client, u.sshNode, repoName)
	require.NoError(u.T(), err)

	err = fleet.VerifyGitRepo(u.client, repoObject.ID, u.cluster.ID, fmt.Sprintf("%s/%s", fleet.Namespace, u.clusterName))
	require.NoError(u.T(), err)

	err = verifyNewGitCommit(u.client, gitStatus.Commit, repoObject.ID)
	require.NoError(u.T(), err)
}

func (u *UpgradeTestSuite) TestGitRepoForceUpdate() {
	u.session = session.NewSession()

	log.Info("Creating new project and namespace")
	_, namespace, err := projectsapi.CreateProjectAndNamespace(u.client, u.cluster.ID)
	require.NoError(u.T(), err)

	log.Info("Cloning Git Repo")
	repoName := namegenerator.AppendRandomString("repo-name")
	_, err = u.sshNode.ExecuteCommand(fmt.Sprintf("cd ~/ && git clone %s %s", fleet.ExampleRepo, repoName))
	require.NoError(u.T(), err)

	log.Info("Creating Fleet repo")
	repoObject, err := createLocalFleetGitRepo(u.client, u.sshNode, repoName, namespace.Name, u.clusterName, u.cluster.ID, u.fleetSecretName)
	require.NoError(u.T(), err)

	log.Info("Getting GitRepo")
	lastRepoObject, err := u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	gitRepo := &v1alpha1.GitRepo{}
	err = steveV1.ConvertToK8sType(lastRepoObject, gitRepo)
	require.NoError(u.T(), err)
	require.NotEmpty(u.T(), gitRepo.Status.Conditions)

	previousUpdateTime, err := time.Parse(time.RFC3339, gitRepo.Status.Conditions[0].LastUpdateTime)
	require.NoError(u.T(), err)

	previousCommit := gitRepo.Status.Commit
	gitRepo.Status.UpdateGeneration++
	gitRepo.Spec.ForceSyncGeneration++

	u.T().Log("Updating Fleet Repo")
	_, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).Update(lastRepoObject, gitRepo)
	require.NoError(u.T(), err)

	err = verifyRepoUpdate(u.client, repoObject.ID)
	require.NoError(u.T(), err)

	log.Info("Getting Last GitRepo")
	lastRepoObject, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	gitRepo = &v1alpha1.GitRepo{}
	err = steveV1.ConvertToK8sType(lastRepoObject, gitRepo)
	require.NoError(u.T(), err)
	require.NotEmpty(u.T(), gitRepo.Status.Conditions)

	lastUpdateTime, err := time.Parse(time.RFC3339, gitRepo.Status.Conditions[0].LastUpdateTime)
	require.NoError(u.T(), err)

	require.Equal(u.T(), previousUpdateTime, lastUpdateTime)
	require.Equal(u.T(), previousCommit, gitRepo.Status.Commit)

	u.T().Log("Verifying the Fleet GitRepo")
	err = fleet.VerifyGitRepo(u.client, repoObject.ID, u.cluster.ID, fmt.Sprintf("%s/%s", fleet.Namespace, u.clusterName))
	require.NoError(u.T(), err)
}

func (u *UpgradeTestSuite) TestPauseFleetRepo() {
	u.session = session.NewSession()

	log.Info("Creating new project and namespace")
	_, namespace, err := projectsapi.CreateProjectAndNamespace(u.client, u.cluster.ID)
	require.NoError(u.T(), err)

	log.Info("Cloning Git Repo")
	repoName := namegenerator.AppendRandomString("repo-name")
	_, err = u.sshNode.ExecuteCommand(fmt.Sprintf("cd ~/ && git clone %s %s", fleet.ExampleRepo, repoName))
	require.NoError(u.T(), err)

	log.Info("Creating Fleet repo")
	repoObject, err := createLocalFleetGitRepo(u.client, u.sshNode, repoName, namespace.Name, u.clusterName, u.cluster.ID, u.fleetSecretName)
	require.NoError(u.T(), err)

	log.Info("Getting GitRepo")
	lastRepoObject, err := u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	gitRepo := &v1alpha1.GitRepo{}
	err = steveV1.ConvertToK8sType(lastRepoObject, gitRepo)
	require.NoError(u.T(), err)

	u.T().Log("Pausing Fleet Repo")
	gitRepo.Spec.Paused = true
	repoObject, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).Update(lastRepoObject, gitRepo)
	require.NoError(u.T(), err)

	err = verifyRepoPause(u.client, repoObject.ID, true)
	require.NoError(u.T(), err)

	log.Info("Fetching latest fleetGitRepo object")
	lastRepoObject, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	log.Info("Checking last GitRepo Paused")
	lastGitRepo := &v1alpha1.GitRepo{}
	err = steveV1.ConvertToK8sType(lastRepoObject, lastGitRepo)
	require.NoError(u.T(), err)
	require.True(u.T(), lastGitRepo.Spec.Paused)
	require.NotEmpty(u.T(), gitRepo.Status.Conditions)

	previousUpdateTime, err := time.Parse(time.RFC3339, gitRepo.Status.Conditions[0].LastUpdateTime)
	require.NoError(u.T(), err)

	err = gitPushCommit(u.client, u.sshNode, repoName)
	require.NoError(u.T(), err)

	log.Info("Fetching latest fleetGitRepo object")
	lastRepoObject, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	log.Info("Checking last GitRepo was not updated")
	lastGitRepo = &v1alpha1.GitRepo{}
	err = steveV1.ConvertToK8sType(lastRepoObject, lastGitRepo)
	require.NoError(u.T(), err)
	require.NotEmpty(u.T(), gitRepo.Status.Conditions)

	lastUpdateTime, err := time.Parse(time.RFC3339, gitRepo.Status.Conditions[0].LastUpdateTime)
	require.NoError(u.T(), err)
	require.Equal(u.T(), lastUpdateTime, previousUpdateTime)

	u.T().Log("Unpausing Fleet Repo")
	lastGitRepo.Spec.Paused = false
	repoObject, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).Update(repoObject, lastGitRepo)
	require.NoError(u.T(), err)

	err = verifyRepoPause(u.client, repoObject.ID, false)
	require.NoError(u.T(), err)

	log.Info("Fetching latest fleetGitRepo object")
	lastRepoObject, err = u.client.Steve.SteveType(extensionsfleet.FleetGitRepoResourceType).ByID(repoObject.ID)
	require.NoError(u.T(), err)

	log.Info("Checking last GitRepo was not updated and unpaused")
	lastGitRepo = &v1alpha1.GitRepo{}
	err = steveV1.ConvertToK8sType(lastRepoObject, lastGitRepo)
	require.NoError(u.T(), err)
	require.True(u.T(), gitRepo.Spec.Paused)
	require.NotEmpty(u.T(), gitRepo.Status.Conditions)

	lastUpdateTime, err = time.Parse(time.RFC3339, gitRepo.Status.Conditions[0].LastUpdateTime)
	require.NoError(u.T(), err)
	require.Equal(u.T(), lastUpdateTime, previousUpdateTime)

	u.T().Log("Verifying the Fleet Repo")
	err = fleet.VerifyGitRepo(u.client, repoObject.ID, u.cluster.ID, fmt.Sprintf("%s/%s", fleet.Namespace, u.clusterName))
	require.NoError(u.T(), err)

	err = verifyNewGitCommit(u.client, gitRepo.Status.Commit, repoObject.ID)
	require.NoError(u.T(), err)
}

func TestUpgradeTestSuite(t *testing.T) {
	suite.Run(t, new(UpgradeTestSuite))
}
