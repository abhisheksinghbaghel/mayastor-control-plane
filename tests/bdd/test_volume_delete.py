"""Volume deletion feature tests."""

from pytest_bdd import (
    given,
    scenario,
    then,
    when,
)

import pytest
import requests
import common

from openapi.openapi_client.model.create_pool_body import CreatePoolBody
from openapi.openapi_client.model.create_volume_body import CreateVolumeBody
from openapi.openapi_client.model.protocol import Protocol
from openapi_client.model.volume_policy import VolumePolicy

POOL_UUID = "4cc6ee64-7232-497d-a26f-38284a444980"
VOLUME_UUID = "5cd5378e-3f05-47f1-a830-a0f5873a1449"
NODE1_NAME = "mayastor-1"
NODE2_NAME = "mayastor-2"
VOLUME_CTX_KEY = "volume"


# This fixture will be automatically used by all tests.
# It starts the deployer which launches all the necessary containers.
# A pool and volume are created for convenience such that it is available for use by the tests.
@pytest.fixture(autouse=True)
def init():
    common.deployer_start(2)
    common.get_pools_api().put_node_pool(
        NODE1_NAME, POOL_UUID, CreatePoolBody(["malloc:///disk?size_mb=50"])
    )
    common.get_volumes_api().put_volume(
        VOLUME_UUID, CreateVolumeBody(VolumePolicy(False), 1, 10485761)
    )
    yield
    common.deployer_stop()


# Fixture used to pass the volume context between test steps.
@pytest.fixture(scope="function")
def volume_ctx():
    return {}


@scenario(
    "features/volume/delete.feature",
    "delete a shared/published volume whilst a replica node is inaccessible",
)
def test_delete_a_sharedpublished_volume_whilst_a_replica_node_is_inaccessible():
    """delete a shared/published volume whilst a replica node is inaccessible."""


@scenario(
    "features/volume/delete.feature",
    "delete a shared/published volume whilst the nexus node is inaccessible",
)
def test_delete_a_sharedpublished_volume_whilst_the_nexus_node_is_inaccessible():
    """delete a shared/published volume whilst the nexus node is inaccessible."""


@scenario(
    "features/volume/delete.feature", "delete a volume that is not shared/published"
)
def test_delete_a_volume_that_is_not_sharedpublished():
    """delete a volume that is not shared/published."""


@scenario("features/volume/delete.feature", "delete a volume that is shared/published")
def test_delete_a_volume_that_is_sharedpublished():
    """delete a volume that is shared/published."""


@given("a volume that is not shared/published")
def a_volume_that_is_not_sharedpublished(volume_ctx):
    """a volume that is not shared/published."""
    volume = volume_ctx[VOLUME_CTX_KEY]
    assert volume is not None
    assert not hasattr(volume.spec, "target")


@given("a volume that is shared/published")
def a_volume_that_is_sharedpublished():
    """a volume that is shared/published."""
    volume = common.get_volumes_api().put_volume_target(
        VOLUME_UUID, NODE1_NAME, Protocol("nvmf")
    )
    assert str(volume.spec.target.protocol) == str(Protocol("nvmf"))


@given("an existing volume")
def an_existing_volume(volume_ctx):
    """an existing volume."""
    volume = common.get_volumes_api().get_volume(VOLUME_UUID)
    assert volume.spec.uuid == VOLUME_UUID
    volume_ctx[VOLUME_CTX_KEY] = volume


@given("an inaccessible node with a volume replica on it")
def an_inaccessible_node_with_a_volume_replica_on_it():
    """an inaccessible node with a volume replica on it."""
    # Nexus is located on node 1 so make node 2 inaccessible as we don't want to disrupt the nexus.
    common.kill_container(NODE2_NAME)


@given("an inaccessible node with the volume nexus on it")
def an_inaccessible_node_with_the_volume_nexus_on_it():
    """an inaccessible node with the volume nexus on it."""
    # Nexus is located on node 1.
    common.kill_container(NODE1_NAME)


@when("a user attempts to delete a volume")
def a_user_attempts_to_delete_a_volume():
    """a user attempts to delete a volume."""
    common.get_volumes_api().del_volume(VOLUME_UUID)


@then("the volume should be deleted")
def the_volume_should_be_deleted():
    """the volume should be deleted."""
    try:
        common.get_volumes_api().get_volume(VOLUME_UUID)
    except Exception as e:
        exception_info = e.__dict__
        assert exception_info["status"] == requests.codes["not_found"]
