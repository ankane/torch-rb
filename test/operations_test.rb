require_relative "test_helper"

class OperationsTest < Minitest::Test
  def test_add
    x = Torch.ones(2)
    assert_equal [2, 2], (x + x).to_a
    assert_equal [2, 2], x.add(x).to_a
    assert_equal [2, 2], Torch.add(x, x).to_a
    assert_equal [3, 3], (x + 2).to_a
    x.add!(x)
    assert_equal [2, 2], x.to_a
  end

  def test_scalar
    x = Torch.tensor([10, 20, 30])
    assert_equal [15, 25, 35], (x + 5).to_a
    assert_equal [5, 15, 25], (x - 5).to_a
    assert_equal [50, 100, 150], (x * 5).to_a
    assert_equal [2, 4, 6], (x / 5).to_a
    assert_equal [1, 2, 0], (x % 3).to_a
    assert_equal [100, 400, 900], (x ** 2).to_a
    assert_equal [-10, -20, -30], (-x).to_a
  end

  def test_sum
    assert_equal 6, Torch.tensor([1, 2, 3]).sum.item
  end

  def test_dot
    assert_equal 7, Torch.dot(Torch.tensor([2, 3]), Torch.tensor([2, 1])).item
  end

  def test_reshape
    x = Torch.ones(6).reshape([2, 3])
    assert_equal [2, 3], x.shape
  end

  def test_accessor
    x = Torch.tensor([[0, 1, 2], [3, 4, 5]])
    assert_equal [0, 1, 2], x[0].to_a
    assert_equal 5, x[1, 2].item
    # TODO support ranges
    # assert_equal [0, 1], x[0, 0..1].to_a
  end
end
